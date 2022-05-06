{ config, pkgs, lib, ... }:

{
  #nixpkgs.overlays = [
  #  (import ./overlay.nix)
  #];

  boot.kernelParams = [
    # Serial console on ttyS2, using the dedicated cable.
    "console=ttyS2,115200"
    "earlycon=uart8250,mmio32,0xff1a0000"
    "earlyprintk"

    "quiet"
    "vt.global_cursor_default=0"
  ];

  hardware.firmware = [
    (pkgs.callPackage ./firmware {})
  ];

  boot.kernelPackages = lib.mkDefault (pkgs.callPackage ./kernel {});

}
