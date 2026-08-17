{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.openWebui;
in
{
  options.lukasf.openWebui = {
    enable = lib.mkEnableOption "Open-WebUI frontend (single owner of services.open-webui)";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start the Open-WebUI systemd service at boot (disable for on-demand use).";
    };

    package = lib.mkPackageOption pkgs "open-webui" { };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address Open-WebUI binds to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port Open-WebUI listens on.";
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/open-webui";
      description = "State directory for Open-WebUI data and uploads.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables for the Open-WebUI service (override backend-provided ones).";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Environment file passed to the Open-WebUI service (for secrets).";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the Open-WebUI port in the firewall.";
    };

    backend = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Name of the backend serving this Open-WebUI instance (set by the claiming backend module, for diagnostics).";
      };

      apiBaseUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "API base URL of the backend serving this Open-WebUI instance (set by the claiming backend module, for diagnostics).";
      };

      extraEnvironment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Backend-provided environment variables for the Open-WebUI service (set by the claiming backend module).";
      };
    };

    backendClaims = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      internal = true;
      description = "Backend modules that registered as the Open-WebUI backend. At most one backend may register.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.length cfg.backendClaims <= 1;
        message = ''
          lukasf.openWebui: more than one backend registered for the single Open-WebUI instance
          (claims: ${lib.concatStringsSep ", " cfg.backendClaims}).
          Enable at most one UI backend, e.g. set lukasf.ollama.ui.enable = false or
          lukasf.llamaCpp.ui.enable = false. Note both backends also default to port 11434.
        '';
      }
    ];

    services.open-webui = {
      enable = true;
      inherit (cfg)
        package
        host
        port
        stateDir
        environmentFile
        openFirewall
        ;
      environment = cfg.backend.extraEnvironment // cfg.environment;
    };

    systemd.services.open-webui = lib.mkIf (!cfg.autoStart) {
      wantedBy = lib.mkForce [ ];
    };
  };
}
