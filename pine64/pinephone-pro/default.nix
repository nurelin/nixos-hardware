{ config, pkgs, lib, modulesPath, ... }:

let 
  ppp-kernel = pkgs.callPackage ./kernel {};
  kernelPath = "${config.boot.kernelPackages.kernel}/" +
    "${config.system.boot.loader.kernelFile}";
  initrdPath = "${config.system.build.initialRamdisk}/" +
    "${config.system.boot.loader.initrdFile}";
  systemRoot = config.system.build.toplevel;
in
{
  imports = [
    ./sd-image
  ];

  boot.kernelParams = [
    # Serial console on ttyS2, using the dedicated cable.
    "console=ttyS2,115200"
    "earlycon=uart8250,mmio32,0xff1a0000"
    "earlyprintk"

    "quiet"
    "vt.global_cursor_default=0"
  ];

  boot.loader.grub.enable = false;
  boot.consoleLogLevel = 7;

  hardware.firmware = [
    (pkgs.callPackage ./firmware {})
  ];

  boot.kernelPackages = pkgs.recurseIntoAttrs (pkgs.linuxPackagesFor ppp-kernel);

  sdImage-efi.populateRootCommands = "";
  sdImage-efi.populateESPCommands = ''
    mkdir -p files/EFI/boot
    ${pkgs.grub2}/bin/grub-mkimage \
      --config="${./grub_early.cfg}" \
      --prefix="" \
      --output="files/EFI/boot/bootaa64.efi" \
      --format="arm64-efi" \
      \
      all_video \
      cat \
      configfile \
      disk \
      echo \
      efi_gop \
      fat \
      gzio \
      help \
      iso9660 \
      linux \
      ls \
      normal \
      part_gpt \
      part_msdos \
      search \
      search_label \
      test \
      true
    cp ${kernelPath} files/EFI/boot/vmlinuz
    cp ${initrdPath} files/EFI/boot/initramfs

    tmp="init=${systemRoot}/init $(cat ${systemRoot}/kernel-params)"

    cat > files/EFI/boot/grub.cfg <<EOF
timeout=0

menuentry "NixOS" {
	linux (\$root)/EFI/boot/vmlinuz $tmp
	initrd (\$root)/EFI/boot/initramfs
}
EOF
  '';
}
