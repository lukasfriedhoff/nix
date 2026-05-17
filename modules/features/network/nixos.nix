{
  config,
  lib,
  ...
}:

let
  cfg = config.shared.network;
in
{
  options.shared.network = {
    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default DNS domain to apply to the host.";
    };

    resolved = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable systemd-resolved with shared defaults.";
      };
      dnssec = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "DNSSEC mode (e.g., \"false\").";
      };
      fallbackDns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Fallback DNS servers for systemd-resolved.";
      };
      networkmanagerDns = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "NetworkManager DNS mode (e.g., \"systemd-resolved\").";
      };
      resolvconfEnable = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Override networking.resolvconf.enable when set.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.domain != null) {
      networking.domain = cfg.domain;
    })
    (lib.mkIf cfg.resolved.enable {
      services.resolved.enable = true;
    })
    (lib.mkIf (cfg.resolved.dnssec != null) {
      services.resolved.settings.Resolve.DNSSEC = cfg.resolved.dnssec;
    })
    (lib.mkIf (cfg.resolved.fallbackDns != [ ]) {
      services.resolved.settings.Resolve.FallbackDNS = cfg.resolved.fallbackDns;
    })
    (lib.mkIf (cfg.resolved.networkmanagerDns != null) {
      networking.networkmanager.dns = cfg.resolved.networkmanagerDns;
    })
    (lib.mkIf (cfg.resolved.resolvconfEnable != null) {
      networking.resolvconf.enable = cfg.resolved.resolvconfEnable;
    })
  ];
}
