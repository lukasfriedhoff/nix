{ config, pkgs, secrets, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/hardware/asus/vivobook-t3300.nix
  ];


  networking.hostName = "tab-h4xx-02";
  boot.initrd.luks.devices."luks-3ec9fc7f-dba1-4c81-9eb0-255731e15fd6".device = "/dev/disk/by-uuid/3ec9fc7f-dba1-4c81-9eb0-255731e15fd6";
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  boot.kernelParams = [ "sdhci.debug_quirks=0x20000" ];

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
    enable = false;
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
