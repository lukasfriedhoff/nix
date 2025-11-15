{ config, pkgs, secrets, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/hardware/tuxedo/infinitybook-pro-16-gen8.nix
    ../../modules/nixos/profiles/desktop/gaming.nix
  ];

  networking.hostName = "tux-h4xx-01";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "ntfs" ];

  desktop.gaming = {
    enable = true;
    defaultRenderer = "nvidia";
  };

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
    address = "10.1.90.2/24";
    privateKeyFile = config.sops.secrets."wireguard-homelab-priv".path;
    dnsDomainFile = config.sops.secrets."wireguard-domain".path;
    endpointFile = config.sops.secrets."wireguard-endpoint".path;
  };

  # Power management
  powerManagement.powertop.enable = true;
  networking.networkmanager.wifi.powersave = true;

  fileSystems."/mnt/windows" = {
    device = "/dev/disk/by-uuid/5C3801A538017F70";
    fsType = "ntfs3";
    options = [
      "rw"
      "uid=1000"
      "gid=100"
      "umask=0022"
      "windows_names"
      "nofail"
      "x-gvfs-show"
    ];
  };

  services.pipewire.extraConfig = {
    pipewire = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 1024;
        "default.clock.min-quantum" = 512;
        "default.clock.max-quantum" = 2048;
      };
    };
    "pipewire-pulse" = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 1024;
      };
      "stream.properties" = {
        "node.latency" = "1024/48000";
        "resample.quality" = 8;
      };
    };
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings = {
      dns_enabled = true;
    };
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
