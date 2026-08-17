{
  config,
  lib,
  secrets ? { },
  myLib ? import ../../../lib { inherit lib; },
  ...
}:

let
  cfg = config.lukasf.nixCache;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    optionalAttrs
    types
    ;

  primaryRoot = secrets.primary or secrets.root or null;
  resolveSecret =
    path:
    myLib.resolveSecretPath {
      root = primaryRoot;
      inherit path;
    };

  defaultHost =
    if cfg.cacheHost != null then
      cfg.cacheHost
    else if config.networking.domain != null && config.networking.domain != "" then
      "${config.networking.hostName}.${config.networking.domain}"
    else
      config.networking.hostName;

  cacheUrl =
    if cfg.cacheUrl != null then cfg.cacheUrl else "http://${defaultHost}:${toString cfg.port}";
in
{
  options.lukasf.nixCache = {
    enable = mkEnableOption "nix-serve binary cache";

    serve = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to run the nix-serve service on this host.";
    };

    secretKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Path to the SOPS-encrypted nix-serve signing key (absolute or relative
        to <option>secrets.primary</option>/<option>secrets.root</option>).
      '';
    };

    publicKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Public cache key in the format <literal>cache-name:BASE64</literal>.
        Required when <option>lukasf.nixCache.configureClient</option> is enabled.
      '';
    };

    cacheHost = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Hostname to advertise in the cache URL (defaults to hostName[/domain]).";
    };

    cacheUrl = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Explicit cache URL (overrides cacheHost/port).";
    };

    port = mkOption {
      type = types.port;
      default = 5000;
      description = "Port used by nix-serve.";
    };

    bindAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Bind address for nix-serve.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the nix-serve port in the firewall.";
    };

    extraParams = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional command line flags passed to nix-serve.";
    };

    configureClient = mkOption {
      type = types.bool;
      default = false;
      description = "Add this cache to the local Nix substituters/trusted keys.";
    };

    connectTimeout = mkOption {
      type = types.int;
      default = 5;
      description = "Connection timeout in seconds for the cache. Lower values provide faster fallback when cache is unavailable.";
    };

    fallbackToOfficial = mkOption {
      type = types.bool;
      default = true;
      description = "Keep cache.nixos.org as fallback substituter (it's always available as default, this option ensures it stays).";
    };
  };

  config = mkIf cfg.enable (
    let
      enableServe = cfg.serve;
    in
    {
      assertions = [
        {
          assertion = (!enableServe) || cfg.secretKeyFile != null;
          message = "lukasf.nixCache.secretKeyFile must be set when nix-serve is enabled.";
        }
        {
          assertion = (!cfg.configureClient) || cfg.publicKey != null;
          message = "lukasf.nixCache.publicKey must be set when configureClient is enabled.";
        }
      ];

      sops.secrets."nix-cache-signing-key" = mkIf (enableServe && cfg.secretKeyFile != null) {
        sopsFile = resolveSecret cfg.secretKeyFile;
        format = "binary";
        mode = "0400";
        owner = "root";
      };

      services.nix-serve = mkIf enableServe {
        enable = true;
        inherit (cfg) bindAddress;
        inherit (cfg) port;
        inherit (cfg) openFirewall;
        secretKeyFile = config.sops.secrets."nix-cache-signing-key".path;
        extraParams = lib.concatStringsSep " " (map lib.escapeShellArg cfg.extraParams);
      };

      nix.settings = mkIf cfg.configureClient (
        {
          substituters = lib.mkBefore [ cacheUrl ];
          # Fast timeout for private cache so we quickly fall back to official
          connect-timeout = cfg.connectTimeout;
        }
        // optionalAttrs (cfg.publicKey != null) {
          trusted-public-keys = lib.mkAfter [ cfg.publicKey ];
        }
      );
    }
  );
}
