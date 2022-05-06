{
  buildLinux
, fetchFromGitLab
, ...
}:

buildLinux {
  version = "5.16.0";
  defconfig = ./config.aarch64;

  src = fetchFromGitLab {
    owner = "pine64-org";
    repo = "linux";
    rev = "cbaae8db31215ed315a8e3f66a075c278a5777ea";
    sha256 = "sha256-w+7MMdGpKs5YpCN6uOCaP0F0GxdiDPiECIm7LLPurGA=";
  };

  kernelPatches = [
    {name = "1"; patch = ./0001-arm64-dts-rockchip-set-type-c-dr_mode-as-otg.patch; }
    {name = "2"; patch = ./0001-usb-dwc3-Enable-userspace-role-switch-control.patch; }
    {name = "3"; patch = ./0001-dts-pinephone-pro-Setup-default-on-and-panic-LEDs.patch; }
  ];

  postInstall = ''
    echo ":: Installing FDTs"
    mkdir -p $out/dtbs/rockchip
    cp -v "$buildRoot/arch/arm64/boot/dts/rockchip/rk3399-pinephone-pro.dtb" "$out/dtbs/rockchip/"
  '';
}
