{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/hardware/asus/vivobook-t3300.nix
  ];

  networking.hostName = "tab-h4xx-02";

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  services.openssh.settings.PasswordAuthentication = false;

  environment.systemPackages = with pkgs; [
    adwaita-icon-theme
  ];
}
