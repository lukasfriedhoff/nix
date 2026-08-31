{
  config,
  lib,
  secrets ? { },
  myLib ? import ../../../lib { inherit lib; },
  ...
}:

let
  cfg = config.desktop.wireguardHomelab;

  primaryRoot = secrets.primary or secrets.root or null;
  sharedRoot = secrets.profileShared or secrets.shared or null;
  wireguardSecretsDir = "/var/lib/sops-nix/wireguard-homelab";

  privateKeyPath = myLib.resolveSecretPath {
    root = primaryRoot;
    path = cfg.privateKeyFile;
  };
  presharedKeyPath = myLib.resolveSecretPath {
    root = primaryRoot;
    path = cfg.presharedKeyFile;
  };
  # PSKs roll out host-by-host (PQ hardening phase 2); hosts without a
  # generated key keep running without one until their secret lands.
  hasPsk = presharedKeyPath != null && builtins.pathExists presharedKeyPath;
  domainPath = myLib.resolveSecretPath {
    root = sharedRoot;
    path = cfg.domainFile;
  };
  endpointPath = myLib.resolveSecretPath {
    root = sharedRoot;
    path = cfg.endpointFile;
  };
in
{
  options.desktop.wireguardHomelab = {
    enable = lib.mkEnableOption "homelab WireGuard client profile";

    address = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "IP address (with CIDR) assigned to this host on the homelab WireGuard network.";
    };

    privateKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "wireguard/homelab.priv";
      description = "Path (absolute or relative to secrets.primary) to the WireGuard private key.";
    };

    presharedKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "wireguard/homelab-psk.txt";
      description = "Path (relative to secrets.primary) to the WireGuard preshared key (post-quantum hardening).";
    };

    domainFile = lib.mkOption {
      type = lib.types.str;
      default = "wireguard/domain.txt";
      description = "Path (absolute or relative to secrets.profileShared) to the DNS search domain file.";
    };

    endpointFile = lib.mkOption {
      type = lib.types.str;
      default = "wireguard/endpoint.txt";
      description = "Path (absolute or relative to secrets.profileShared) to the WireGuard endpoint file.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.address != null;
        message = "desktop.wireguardHomelab.address must be set when enabling the homelab WireGuard profile.";
      }
    ];

    sops.secrets."wireguard-homelab-priv" = {
      sopsFile = privateKeyPath;
      owner = "root";
      format = "binary";
      mode = "0400";
      path = "${wireguardSecretsDir}/private-key";
    };

    sops.secrets."wireguard-homelab-psk" = lib.mkIf hasPsk {
      sopsFile = presharedKeyPath;
      owner = "root";
      format = "binary";
      mode = "0400";
      path = "${wireguardSecretsDir}/preshared-key";
    };

    sops.secrets."wireguard-domain" = {
      sopsFile = domainPath;
      owner = "root";
      format = "binary";
      mode = "0400";
      path = "${wireguardSecretsDir}/domain";
    };

    sops.secrets."wireguard-endpoint" = {
      sopsFile = endpointPath;
      owner = "root";
      format = "binary";
      mode = "0400";
      path = "${wireguardSecretsDir}/endpoint";
    };

    systemd.tmpfiles.rules = [
      "d ${wireguardSecretsDir} 0700 root root -"
    ];

    lukasf.wireguard.homelab = {
      enable = true;
      inherit (cfg) address;
      privateKeyFile = config.sops.secrets."wireguard-homelab-priv".path;
      presharedKeyFile = lib.mkIf hasPsk config.sops.secrets."wireguard-homelab-psk".path;
      dnsDomainFile = config.sops.secrets."wireguard-domain".path;
      endpointFile = config.sops.secrets."wireguard-endpoint".path;
    };
  };
}
