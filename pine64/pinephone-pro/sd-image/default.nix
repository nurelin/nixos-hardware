# This module creates a bootable SD card image containing the given NixOS
# configuration. The generated image is MBR partitioned, with a FAT
# /boot/firmware partition, and ext4 root partition. The generated image
# is sized to fit its contents, and a boot script automatically resizes
# the root partition to fit the device on the first boot.
#
# The firmware partition is built with expectation to hold the Raspberry
# Pi firmware and bootloader, and be removed and replaced with a firmware
# build for the target SoC for other board families.
#
# The derivation for the SD image will be placed in
# config.system.build.sdImage-efi

{ config, lib, pkgs, modulesPath, ... }:

with lib;

let
  rootfsImage = pkgs.callPackage "${modulesPath}/../lib/make-ext4-fs.nix" ({
    inherit (config.sdImage-efi) storePaths;
    compressImage = true;
    populateImageCommands = config.sdImage-efi.populateRootCommands;
    volumeLabel = "NIXOS_SD";
  } // optionalAttrs (config.sdImage-efi.rootPartitionUUID != null) {
    uuid = config.sdImage-efi.rootPartitionUUID;
  });

  espFSImage = pkgs.callPackage ./make-esp-fs.nix {
    populateESPCommands = config.sdImage-efi.populateESPCommands;
  };
in
{
  imports = [
    "${modulesPath}/profiles/base.nix"
    "${modulesPath}/profiles/all-hardware.nix"
  ];

  options.sdImage-efi = {
    imageName = mkOption {
      default = "${config.sdImage-efi.imageBaseName}-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.img";
      description = ''
        Name of the generated image file.
      '';
    };

    imageBaseName = mkOption {
      default = "nixos-sd-image";
      description = ''
        Prefix of the name of the generated image file.
      '';
    };

    storePaths = mkOption {
      type = with types; listOf package;
      example = literalExpression "[ pkgs.stdenv ]";
      description = ''
        Derivations to be included in the Nix store in the generated SD image.
      '';
    };

    ESPOffset = mkOption {
      type = types.int;
      default = 8;
      description = ''
        Gap in front of the ESP partition, in mebibytes (1024×1024
        bytes).
      '';
    };

    ESPID = mkOption {
      type = types.str;
      default = "0x2178694e";
      description = ''
        Volume ID for the /boot/firmware partition on the SD card. This value
        must be a 32-bit hexadecimal number.
      '';
    };

    ESPName = mkOption {
      type = types.str;
      default = "ESP";
      description = ''
        Name of the filesystem which holds the ESP.
      '';
    };

    ESPSize = mkOption {
      type = types.int;
      default = 300;
      description = ''
        Size of the ESP partition, in megabytes.
      '';
    };

    populateESPCommands = mkOption {
      example = literalExpression "'' cp \${pkgs.myBootLoader}/u-boot.bin firmware/ ''";
      description = ''
        Shell commands to populate the ./firmware directory.
        All files in that directory are copied to the
        /boot/firmware partition on the SD image.
      '';
    };

    rootPartitionSize = mkOption {
      type = types.int;
      default = 3400;
      description = ''
        Size of the root partition, in megabytes.
      '';
    };

    rootPartitionUUID = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "14e19a7b-0ae0-484d-9d54-43bd6fdc20c7";
      description = ''
        UUID for the filesystem on the main NixOS partition on the SD card.
      '';
    };

    populateRootCommands = mkOption {
      example = literalExpression "''\${config.boot.loader.generic-extlinux-compatible.populateCmd} -c \${config.system.build.toplevel} -d ./files/boot''";
      description = ''
        Shell commands to populate the ./files directory.
        All files in that directory are copied to the
        root (/) partition on the SD image. Use this to
        populate the ./files/boot (/boot) directory.
      '';
    };

    postBuildCommands = mkOption {
      example = literalExpression "'' dd if=\${pkgs.myBootLoader}/SPL of=$img bs=1024 seek=1 conv=notrunc ''";
      default = "";
      description = ''
        Shell commands to run after the image is built.
        Can be used for boards requiring to dd u-boot SPL before actual partitions.
      '';
    };

    compressImage = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether the SD image should be compressed using
        <command>zstd</command>.
      '';
    };

    expandOnBoot = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to configure the sd image to expand it's partition on boot.
      '';
    };
  };

  config = {
    fileSystems = {
      "/boot" = {
        device = "/dev/disk/by-label/${config.sdImage-efi.ESPName}";
        fsType = "vfat";
        # Alternatively, this could be removed from the configuration.
        # The filesystem is not needed at runtime, it could be treated
        # as an opaque blob instead of a discrete FAT32 filesystem.
        options = [ "nofail" "noauto" ];
      };
      "/" = {
        device = "/dev/disk/by-label/NIXOS_SD";
        fsType = "ext4";
      };
    };

    sdImage-efi.storePaths = [ config.system.build.toplevel ];

    system.build.sdImage-efi-esp = espFSImage;
    system.build.sdImage-efi = pkgs.callPackage ({ stdenv, dosfstools, e2fsprogs,
    mtools, libfaketime, util-linux, zstd, gptfdisk, parted }: stdenv.mkDerivation {
      name = config.sdImage-efi.imageName;

      nativeBuildInputs = [ gptfdisk parted dosfstools e2fsprogs mtools libfaketime util-linux zstd ];

      inherit (config.sdImage-efi) imageName compressImage;

      buildCommand = ''
        mkdir -p $out/nix-support $out/sd-image
        export img=$out/sd-image/${config.sdImage-efi.imageName}

        echo "${pkgs.stdenv.buildPlatform.system}" > $out/nix-support/system
        if test -n "$compressImage"; then
          echo "file sd-image $img.zst" >> $out/nix-support/hydra-build-products
        else
          echo "file sd-image $img" >> $out/nix-support/hydra-build-products
        fi

        echo "Decompressing rootfs image"
        zstd -d --no-progress "${rootfsImage}" -o ./root-fs.img

        # Gap in front of the first partition, in MiB
        gap=${toString config.sdImage-efi.ESPOffset}

        # Create the image file sized to fit ESP and root, plus slack for the gap.
        MB=$((1000 * 1000))
        MiB=$((1024 * 1024))

        set -x

        ESPImageSize=$(du -b ${espFSImage} | awk '{ print $1 }')
        ESPSize=$((${toString config.sdImage-efi.ESPSize} * MB))
        ESPEnd=$((gap * MiB + ESPSize))

        if [ "$ESPSize" -lt "$ESPImageSize" ]; then
          echo "Size of image is larger ($ESPImageSize) than asked ESP partition ($ESPSize)"
          exit 1
        fi

        rootImageSize=$(du -b ./root-fs.img | awk '{ print $1 }')
        rootSize=$((${toString config.sdImage-efi.rootPartitionSize} * MB))
        rootEnd=$((ESPEnd + rootSize))

        if [ "$rootSize" -lt "$rootImageSize" ]; then
          echo "Size of image is larger ($rootImageSize) than asked root partition ($rootSize)"
          exit 1
        fi

        imageSize=$(($rootEnd + 1000))
        truncate -s $imageSize $img

        parted \
          --machine \
          --script \
          "$img" \
          mklabel gpt \
          mkpart ESP fat32 ''${gap}MiB ''${ESPEnd}B \
          set 1 boot on \
          mkpart "NIXOS_SD" ext4 $((ESPEnd +1000))B 100%

        # Copy the ESP into the SD image
        eval $(partx $img -o START,SECTORS --nr 1 --pairs)
        dd conv=notrunc if=${espFSImage} of=$img seek=$START count=$SECTORS

        # Copy the rootfs into the SD image
        eval $(partx $img -o START,SECTORS --nr 2 --pairs)
        dd conv=notrunc if=./root-fs.img of=$img seek=$START count=$SECTORS

        ${config.sdImage-efi.postBuildCommands}

        if test -n "$compressImage"; then
            zstd -T$NIX_BUILD_CORES --rm $img
        fi
      '';
    }) {};

    boot.postBootCommands = lib.mkIf config.sdImage-efi.expandOnBoot ''
      # On the first boot do some maintenance tasks
      if [ -f /nix-path-registration ]; then
        set -euo pipefail
        set -x
        # Figure out device names for the boot device and root filesystem.
        rootPart=$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE /)
        bootDevice=$(lsblk -npo PKNAME $rootPart)
        partNum=$(lsblk -npo MAJ:MIN $rootPart | ${pkgs.gawk}/bin/awk -F: '{print $2}')

        # Resize the root partition and the filesystem to fit the disk
        echo ",+," | sfdisk -N$partNum --no-reread $bootDevice
        ${pkgs.parted}/bin/partprobe
        ${pkgs.e2fsprogs}/bin/resize2fs $rootPart

        # Register the contents of the initial Nix store
        ${config.nix.package.out}/bin/nix-store --load-db < /nix-path-registration

        # nixos-rebuild also requires a "system" profile and an /etc/NIXOS tag.
        touch /etc/NIXOS
        ${config.nix.package.out}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system

        # Prevents this from running on later boots.
        rm -f /nix-path-registration
      fi
    '';
  };
}
