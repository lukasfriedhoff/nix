{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/hardware/tuxedo/infinitybook-pro-16-gen8.nix
    ../../modules/nixos/profiles/desktop/gaming.nix
  ];

  networking.hostName = "tux-h4xx-01";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  desktop.gaming.enable = true;
}
