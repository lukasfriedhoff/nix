{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.ollama;
  # Select ollama package based on acceleration setting
  ollamaPackage =
    if cfg.acceleration == "cuda" then
      pkgs.ollama-cuda
    else if cfg.acceleration == "rocm" then
      pkgs.ollama-rocm
    else if cfg.acceleration == null || builtins.elem cfg.acceleration [ false ] then
      pkgs.ollama-cpu
    else
      cfg.package;
in
{
  options.lukasf.ollama = {
    enable = lib.mkEnableOption "Ollama server with Open-WebUI frontend";
    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start the Ollama systemd service at boot (disable for on-demand use).";
    };

    package = lib.mkPackageOption pkgs "ollama" { };
    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address Ollama binds to.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "Port Ollama listens on.";
    };
    rocmOverrideGfx = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Override ROCm GPU detection (sets HSA_OVERRIDE_GFX_VERSION).";
    };
    loadModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Models to pre-pull via ollama-model-loader.";
    };
    syncModels = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Remove undeclared models when loadModels is set.";
    };
    environmentVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables for the Ollama systemd unit.";
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the Ollama API port in the firewall.";
    };

    acceleration = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "cuda"
          "rocm"
          false
        ]
      );
      default = null;
      description = "GPU acceleration backend: 'cuda' for NVIDIA, 'rocm' for AMD, false to disable.";
    };

    ui = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Open-WebUI as a frontend for Ollama.";
      };
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
      ollamaUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        defaultText = lib.literalExpression "http://\${config.lukasf.ollama.host}:\${toString config.lukasf.ollama.port}";
        description = "Base URL for the Ollama API (default derived from host/port).";
      };
      environment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Extra environment variables for the Open-WebUI service.";
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
    };
  };

  config = lib.mkIf cfg.enable (
    let
      resolvedOllamaUrl =
        if cfg.ui.ollamaUrl != null then cfg.ui.ollamaUrl else "http://${cfg.host}:${toString cfg.port}";
    in
    {
      services.ollama = {
        enable = true;
        package = ollamaPackage;
        inherit (cfg) host;
        inherit (cfg) port;
        inherit (cfg) rocmOverrideGfx;
        inherit (cfg) loadModels;
        inherit (cfg) syncModels;
        inherit (cfg) environmentVariables;
        inherit (cfg) openFirewall;
      };

      services.open-webui = lib.mkIf cfg.ui.enable {
        enable = true;
        inherit (cfg.ui) package;
        inherit (cfg.ui) host;
        inherit (cfg.ui) port;
        inherit (cfg.ui) stateDir;
        inherit (cfg.ui) environmentFile;
        inherit (cfg.ui) openFirewall;
        environment = {
          OLLAMA_API_BASE_URL = resolvedOllamaUrl;
        }
        // cfg.ui.environment;
      };

      systemd.services.ollama = lib.mkIf (!cfg.autoStart) {
        wantedBy = lib.mkForce [ ];
      };

      systemd.services.open-webui = lib.mkIf (cfg.ui.enable && !cfg.ui.autoStart) {
        wantedBy = lib.mkForce [ ];
      };
    }
  );
}
