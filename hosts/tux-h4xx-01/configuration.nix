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
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 10;
  boot.loader.generic-extlinux-compatible.configurationLimit = lib.mkDefault 10;
  boot.loader.grub.configurationLimit = lib.mkDefault 10;

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
    cacheHost = "srv1.lab.h4xx.io";
    publicKey = builtins.readFile ../../resources/nix-cache/personal-cache.pub;
  };

  lukasf.remoteBuilds.sshKeyFile = config.sops.secrets."srv1-builder-key".path;
  lukasf.remoteBuilds.publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSURZeXEvNm9XNS9vTkhMazZOM1FLaWFjSVBnaEkrdW9VTlY1T0MyRXI0YUEgcm9vdEBuaXhvcwo=";

  # Ceph client credentials for RBD access from tux.
  sops.secrets."ceph/client-tux-keyring" = {
    sopsFile = ../../secrets/profiles/personal/desktops/tux-h4xx-01/ceph/client.tux.keyring.txt;
    owner = "root";
    mode = "0400";
    path = "/etc/ceph/ceph.client.tux.keyring";
    format = "binary";
  };

  # User-readable copy for CLI use (rbd/rados) without sudo.
  sops.secrets."ceph/client-tux-keyring-user" = {
    sopsFile = ../../secrets/profiles/personal/desktops/tux-h4xx-01/ceph/client.tux.keyring.txt;
    owner = "lukasf";
    mode = "0600";
    path = "/home/lukasf/.ceph/ceph.client.tux.keyring";
    format = "binary";
  };

  # Ensure ~/.ceph exists for the user keyring.
  systemd.tmpfiles.rules = [
    "d /home/lukasf/.ceph 0700 lukasf users -"
  ];

  # Minimal Ceph config for user tools (defaults to srv1 mon on 3300).
  environment.etc."ceph/ceph.conf".text = ''
    [global]
    mon_host = srv1.lab.h4xx.io:3300
  '';

  lukasf.ceph.client = {
    enable = true;
    monHosts = [ "srv1.lab.h4xx.io" ];
    monPort = 3300;
    publicNetwork = "10.1.30.0/24";
  };

  programs.ssh.knownHosts.srv1 = {
    hostNames = [
      "srv1"
      "srv1.lab.h4xx.io"
      "10.1.30.12"
    ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDYyq/6oW5/oNHLk6N3QKiacIPghI+uoUNV5OC2Er4aA";
  };

  # Power management
  powerManagement.powertop.enable = true;
  networking.networkmanager.wifi.powersave = true;

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
    libvirt
    ceph
    smartmontools
  ];

  networking.networkmanager.dns = "systemd-resolved";
  networking.resolvconf.enable = lib.mkForce false;

  # Keep the Windows partition declared so the unit exists, but avoid
  # automounting or blocking boots/switches if the volume is dirty.
  # Define explicit units for the Windows partition so the unit files exist in
  # the generation that switch-to-configuration references.
  systemd.mounts = [
    {
      what = "/dev/disk/by-uuid/5C3801A538017F70";
      where = "/mnt/windows";
      type = "ntfs3";
      options = "noauto,nofail,x-systemd.device-timeout=1s";
      wantedBy = [ ];
    }
  ];

  systemd.automounts = [
    {
      where = "/mnt/windows";
      wantedBy = [ "multi-user.target" ];
      automountConfig.IdleTimeoutSec = "1min";
    }
  ];
}
