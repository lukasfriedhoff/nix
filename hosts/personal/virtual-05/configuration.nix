{
  inputs,
  lib,
  ...
}:

{
  imports = [
    ../../common/default.nix
    ./hardware-configuration.nix
    inputs.disko.nixosModules.disko
    ./disko.nix
  ];

  networking.hostName = "virtual-05";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 10;
  boot.loader.generic-extlinux-compatible.configurationLimit = lib.mkDefault 10;
  boot.loader.grub.configurationLimit = lib.mkDefault 10;

  desktop.personalWorkstation = {
    enable = true;
    wireguardAddress = "10.1.90.6/24";
    cephClientName = "virtual-05";
  };

  lukasf.wireguard.homelab.userUnit.enable = true;

  users.users.lukasf.extraGroups = lib.mkAfter [
    "input"
  ];

  boot.kernelModules = [ "uinput" ];
  services.udev.extraRules = ''
    KERNEL=="uinput", MODE="0660", GROUP="input"
  '';
}
