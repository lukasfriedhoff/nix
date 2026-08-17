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
      description = ''
        Port Ollama listens on. Defaults to 11434 (the upstream Ollama default).
        Note lukasf.llamaCpp also defaults to 11434 for Ollama-compatibility; do
        not enable both backends on the same host without changing one port.
      '';
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
        description = ''
          Register Ollama as the backend for the shared Open-WebUI frontend
          (lukasf.openWebui). Configure the frontend itself (host, port,
          autoStart, firewall, ...) via the lukasf.openWebui.* options.
        '';
      };
      ollamaUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        defaultText = lib.literalExpression "http://\${config.lukasf.ollama.host}:\${toString config.lukasf.ollama.port}";
        description = "Base URL for the Ollama API used by Open-WebUI (default derived from host/port).";
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

      lukasf.openWebui = lib.mkIf cfg.ui.enable {
        enable = true;
        backend = {
          name = "ollama";
          apiBaseUrl = resolvedOllamaUrl;
          extraEnvironment = {
            OLLAMA_API_BASE_URL = resolvedOllamaUrl;
          };
        };
        backendClaims = [ "lukasf.ollama" ];
      };

      systemd.services.ollama = lib.mkIf (!cfg.autoStart) {
        wantedBy = lib.mkForce [ ];
      };
    }
  );
}
