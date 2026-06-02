{
  config,
  lib,
  pkgs,
  secrets ? { },
  ...
}:

let
  cfg = config.lukasf.atticCache;
  inherit (lib)
    getExe
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;

  primaryRoot = secrets.primary or secrets.root or null;
  resolveSecret =
    path:
    if path == null then
      null
    else if lib.hasPrefix "/" path then
      path
    else if primaryRoot != null then
      "${primaryRoot}/${path}"
    else
      throw "lukasf.atticCache: relative secret '${path}' requires secrets.primary/root";

  cacheUrl = "${cfg.serverUrl}/${cfg.cacheName}?priority=${toString cfg.priority}";
in
{
  options.lukasf.atticCache = {
    enable = mkEnableOption "Attic binary cache integration";

    serve = mkOption {
      type = types.bool;
      default = false;
      description = "Run the Attic cache server on this host.";
    };

    configureClient = mkOption {
      type = types.bool;
      default = true;
      description = "Configure this host to use the Attic cache as a Nix substituter.";
    };

    serverUrl = mkOption {
      type = types.str;
      default = "https://attic.h4xx.io";
      description = "Public Attic server URL.";
    };

    cacheName = mkOption {
      type = types.str;
      default = "homelab";
      description = "Attic cache name.";
    };

    publicKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Attic cache public key from `attic cache info`.";
    };

    priority = mkOption {
      type = types.int;
      default = 30;
      description = "Substituter priority advertised to Nix.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "SOPS file containing ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64.";
    };

    tokenFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional SOPS file containing an Attic client token for upload jobs.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0:8080";
      description = "Attic listen address.";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Attic HTTP port to open when openFirewall is enabled.";
    };

    storagePath = mkOption {
      type = types.path;
      default = "/var/lib/atticd/storage";
      description = "Local Attic storage path.";
    };

    databaseUrl = mkOption {
      type = types.str;
      default = "sqlite:///var/lib/atticd/server.db?mode=rwc";
      description = "Attic database URL.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the Attic HTTP port in the firewall.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      environment.systemPackages = [ pkgs.attic-client ];
    }

    (mkIf cfg.serve {
      assertions = [
        {
          assertion = cfg.environmentFile != null;
          message = "lukasf.atticCache.environmentFile must point at an Attic server environment secret.";
        }
      ];

      sops.secrets."attic-server-token-rs256-secret-base64" = {
        sopsFile = resolveSecret cfg.environmentFile;
        format = "dotenv";
        key = "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64";
        mode = "0400";
        owner = "root";
      };

      sops.templates."attic-server.env" = {
        content = ''
          ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=${
            config.sops.placeholder."attic-server-token-rs256-secret-base64"
          }
        '';
        mode = "0400";
        owner = "root";
      };

      services.atticd = {
        enable = true;
        environmentFile = config.sops.templates."attic-server.env".path;
        settings = {
          listen = cfg.listenAddress;
          "api-endpoint" = cfg.serverUrl;
          database.url = cfg.databaseUrl;
          storage = {
            type = "local";
            path = cfg.storagePath;
          };
        };
      };

      networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
    })

    (mkIf (cfg.configureClient && cfg.publicKey != null) {
      nix.settings = {
        substituters = lib.mkBefore [ cacheUrl ];
        trusted-public-keys = lib.mkAfter [ cfg.publicKey ];
      };
    })

    (mkIf (cfg.tokenFile != null) {
      sops.secrets."attic-client-token" = {
        sopsFile = resolveSecret cfg.tokenFile;
        format = "binary";
        mode = "0400";
        owner = "root";
      };

      environment.etc."attic/login-homelab-cache".source =
        pkgs.writeShellScript "attic-login-homelab-cache" ''
          set -euo pipefail
          token="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "${config.sops.secrets."attic-client-token".path}")"
          exec ${getExe pkgs.attic-client} login ${lib.escapeShellArg cfg.cacheName} ${lib.escapeShellArg cfg.serverUrl} "$token"
        '';
    })
  ]);
}
