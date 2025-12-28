{
  config,
  pkgs,
  lib,
  secrets,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # LUKS (keep your UUID)
  boot.initrd.luks.devices."luks-84295891-6d10-4a08-a2fc-442738205455".device =
    "/dev/disk/by-uuid/84295891-6d10-4a08-a2fc-442738205455";

  networking.hostName = "nix-vm-01";

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
    address = "10.1.90.4/24";
    privateKeyFile = config.sops.secrets."wireguard-homelab-priv".path;
    dnsDomainFile = config.sops.secrets."wireguard-domain".path;
    endpointFile = config.sops.secrets."wireguard-endpoint".path;
  };

  sops.age.keyFile = "/home/lukasf/.config/sops/age/keys.txt";

  services.resolved = {
    enable = true;
    dnssec = "false";
    fallbackDns = [
      "1.1.1.1"
      "9.9.9.9"
    ];
  };
  networking.networkmanager.dns = "systemd-resolved";
  networking.resolvconf.enable = lib.mkForce false;
}
