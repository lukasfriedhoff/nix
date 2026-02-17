{
  inputs,
  lib,
  ...
}:

let
  facterReport = ./facter.json;
in
{
  imports = [
    ../../common/default.nix
    ./hardware-configuration.nix
    inputs.nixos-facter-modules.nixosModules.facter
    inputs.disko.nixosModules.disko
    ./disko.nix
    ../../../modules/nixos/hardware/lenovo/thinkpad-p15-gen2i.nix
    ../../../modules/nixos/profiles/desktop/gaming.nix
  ];

  config = lib.mkMerge [
    {
      networking.hostName = "lenovo-h4xx-03";

      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.systemd-boot.configurationLimit = lib.mkDefault 10;
      boot.loader.generic-extlinux-compatible.configurationLimit = lib.mkDefault 10;
      boot.loader.grub.configurationLimit = lib.mkDefault 10;
      boot.resumeDevice = "/dev/mapper/vg0-swap";

      desktop.personalWorkstation = {
        enable = true;
        wireguardAddress = "10.1.90.5/24";
        cephClientName = "lenovo";
      };

      desktop.gaming.defaultRenderer = "nvidia";
    }
    (lib.mkIf (builtins.pathExists facterReport) {
      hardware.facter.reportPath = facterReport;
    })
  ];
}
