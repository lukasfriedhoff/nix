{
  config,
  pkgs,
  secrets,
  lib,
  ...
}:

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
  sops.secrets."srv1-builder-key" = {
    sopsFile = "${secrets.profileCommon}/ssh/srv1-personal-mgmt.priv";
    owner = "root";
    format = "binary";
    mode = "0400";
  };

  lukasf.wireguard.homelab = {
    enable = true;
    address = "10.1.90.2/24";
    privateKeyFile = config.sops.secrets."wireguard-homelab-priv".path;
    dnsDomainFile = config.sops.secrets."wireguard-domain".path;
    endpointFile = config.sops.secrets."wireguard-endpoint".path;
  };

  lukasf.nixCache = {
    enable = true;
    serve = false;
    configureClient = true;
    cacheHost = "srv1.h4xx.local";
    publicKey = builtins.readFile ../../resources/nix-cache/personal-cache.pub;
  };

  lukasf.remoteBuilds.sshKeyFile = config.sops.secrets."srv1-builder-key".path;
  lukasf.remoteBuilds.publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSURZeXEvNm9XNS9vTkhMazZOM1FLaWFjSVBnaEkrdW9VTlY1T0MyRXI0YUEgcm9vdEBuaXhvcwo=";

  programs.ssh.knownHosts.srv1 = {
    hostNames = [
      "srv1"
      "srv1.h4xx.local"
      "10.1.30.12"
    ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDYyq/6oW5/oNHLk6N3QKiacIPghI+uoUNV5OC2Er4aA";
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
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=10min"
      "x-systemd.device-timeout=1s"
      "x-gvfs-show"
    ];
  };

  services.pipewire.extraConfig = {
    pipewire = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 2048;
        "default.clock.min-quantum" = 1024;
        "default.clock.max-quantum" = 2048;
      };
    };
    "pipewire-pulse" = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 2048;
      };
      "stream.properties" = {
        "node.latency" = "2048/48000";
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
    fallbackDns = [
      "1.1.1.1"
      "9.9.9.9"
    ];
  };
  environment.systemPackages = with pkgs; [
    smartmontools
  ];

  networking.networkmanager.dns = "systemd-resolved";
  networking.resolvconf.enable = lib.mkForce false;
}
