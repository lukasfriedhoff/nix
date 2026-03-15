{
  config,
  lib,
  secrets ? { },
  ...
}:

let
  cfg = config.desktop.wireguardHomelab;

  primaryRoot = secrets.primary or secrets.root or null;
  sharedRoot = secrets.profileShared or secrets.shared or null;
  wireguardSecretsDir = "/var/lib/sops-nix/wireguard-homelab";

  resolveSecret =
    root: file:
    if lib.hasPrefix "/" file then
      file
    else if root != null then
      "${root}/${file}"
    else
      throw "desktop.wireguardHomelab: relative secret '${file}' requires a secrets root";

  privateKeyPath = resolveSecret primaryRoot cfg.privateKeyFile;
  domainPath = resolveSecret sharedRoot cfg.domainFile;
  endpointPath = resolveSecret sharedRoot cfg.endpointFile;
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
      dnsDomainFile = config.sops.secrets."wireguard-domain".path;
      endpointFile = config.sops.secrets."wireguard-endpoint".path;
    };
  };
}
