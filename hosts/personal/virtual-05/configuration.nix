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

  # uinput, the input group and the kernel module now come from
  # lukasf.sunshine — Sunshine needs them to synthesise keyboard and mouse
  # events, so they belong with the feature rather than duplicated per host.
  lukasf.sunshine = {
    enable = true;
    openFirewall = true;
    # srv8's Radeon (renoir) advertises H.264 and HEVC EncSlice; the userspace
    # driver comes from this image's mesa, not from the host.
    vaapiDevice = "/dev/dri/renderD128";
    headless = {
      enable = true;
      user = "lukasf";
    };
  };
}
