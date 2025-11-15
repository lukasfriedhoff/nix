{ config, pkgs, secrets, lib, ... }:

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

  sops.secrets."wireguard-homelab-priv" = {
    sopsFile = "${secrets.primary}/wireguard/homelab.priv";
    owner = "root";
    format = "binary";
  };
  sops.secrets."wireguard-domain" = {
    sopsFile = "${secrets.shared}/wireguard/domain.txt";
    owner = "root";
    format = "binary";
  };
  sops.secrets."wireguard-endpoint" = {
    sopsFile = "${secrets.shared}/wireguard/endpoint.txt";
    owner = "root";
    format = "binary";
  };

  lukasf.wireguard.homelab = {
    enable = true;
    address = "10.1.90.3/24";
    privateKeyFile = config.sops.secrets."wireguard-homelab-priv".path;
    dnsDomainFile = config.sops.secrets."wireguard-domain".path;
    endpointFile = config.sops.secrets."wireguard-endpoint".path;
  };

  sops.age.keyFile = "/home/lukasf/.config/sops/age/keys.txt";

  services.resolved = {
    enable = true;
    dnssec = "false";
    fallbackDns = [ "1.1.1.1" "9.9.9.9" ];
  };
  networking.networkmanager.dns = "systemd-resolved";
  networking.resolvconf.enable = lib.mkForce false;
}
