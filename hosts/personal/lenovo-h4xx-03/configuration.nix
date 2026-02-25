{
  config,
  inputs,
  lib,
  secrets,
  ...
}:

{
  imports = [
    ../../common/default.nix
    ./hardware-configuration.nix
    inputs.disko.nixosModules.disko
    ./disko.nix
  ];

  networking.hostName = "lenovo-h4xx-03";

  hardwareProfiles.lenovo.thinkpadP15Gen2i.enable = true;

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

  lukasf.kvm.enable = true;

  users.users.lukasf.extraGroups = lib.mkAfter [
    "libvirtd"
    "kvm"
  ];

  users.users.lukasf.hashedPassword = "$6$yzoypuzQDaJPoH3Q$jMjF9ciENiSRMMDfkeJJdGb9jMK1W35kNLvO3gH4B58rhWj285gYBI6n8.i8ry8jG5f7Ll3VxNbdvX5Sp2aGs0";
}
