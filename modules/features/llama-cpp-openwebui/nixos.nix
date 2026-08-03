{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.llamaCpp;

  llamaPackage =
    if cfg.acceleration == "rocm" then
      pkgs.llama-cpp-rocm
    else if cfg.acceleration == "vulkan" then
      pkgs.llama-cpp-vulkan
    else
      cfg.package;

  listenHostForLocalClients = if cfg.host == "0.0.0.0" then "127.0.0.1" else cfg.host;
  defaultLlamaCppBaseUrl = "http://${listenHostForLocalClients}:${toString cfg.port}/v1";
  resolvedLlamaCppBaseUrl =
    if cfg.ui.llamaCppBaseUrl != null then cfg.ui.llamaCppBaseUrl else defaultLlamaCppBaseUrl;

  defaultModelsPreset = {
    "qwen3-coder:30b" = {
      hf-repo = "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF";
      hf-file = "Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf";
      alias = "qwen3-coder:30b,qwen3-coder";
      c = "32768";
      fit = "on";
      jinja = "on";
      temp = "0.2";
      top-p = "0.95";
      min-p = "0.01";
    };

    "qwen3-coder:30b-quality" = {
      hf-repo = "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF";
      hf-file = "Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf";
      alias = "qwen3-coder:30b-quality";
      c = "32768";
      fit = "on";
      jinja = "on";
      temp = "0.2";
      top-p = "0.95";
      min-p = "0.01";
    };

    "qwen3:8b" = {
      hf-repo = "Qwen/Qwen3-8B-GGUF";
      hf-file = "Qwen3-8B-Q4_K_M.gguf";
      alias = "qwen3:8b,qwen3-fast";
      c = "32768";
      fit = "on";
      jinja = "on";
    };

    "qwen3:30b" = {
      hf-repo = "Qwen/Qwen3-30B-A3B-GGUF";
      hf-file = "Qwen3-30B-A3B-Q4_K_M.gguf";
      alias = "qwen3:30b";
      c = "32768";
      fit = "on";
      jinja = "on";
    };
  };
in
{
  options.lukasf.llamaCpp = {
    enable = lib.mkEnableOption "llama.cpp server with Open WebUI frontend";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start the llama.cpp systemd service at boot.";
    };

    package = lib.mkPackageOption pkgs "llama-cpp" { };

    acceleration = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "rocm"
          "vulkan"
          false
        ]
      );
      default = null;
      description = "llama.cpp acceleration package to use. Set false to force the base CPU package.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address llama.cpp binds to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "Port llama.cpp listens on.";
    };

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "qwen3:8b";
      description = "Default model alias used by clients and Open WebUI.";
    };

    modelsDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Directory with local GGUF models for the llama.cpp router.";
    };

    modelsPreset = lib.mkOption {
      type = lib.types.nullOr (lib.types.attrsOf lib.types.attrs);
      default = defaultModelsPreset;
      description = "llama-server model preset entries for favorite GGUF models.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--models-max"
        "2"
        "--cache-ram"
        "8192"
        "--parallel"
        "2"
        "--cont-batching"
      ];
      description = "Extra flags passed to llama-server.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the llama.cpp API port in the firewall.";
    };

    ui = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Open WebUI as a frontend for llama.cpp.";
      };

      autoStart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Start the Open WebUI systemd service at boot.";
      };

      package = lib.mkPackageOption pkgs "open-webui" { };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Address Open WebUI binds to.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "Port Open WebUI listens on.";
      };

      stateDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/open-webui";
        description = "State directory for Open WebUI data and uploads.";
      };

      llamaCppBaseUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        defaultText = lib.literalExpression "http://\${config.lukasf.llamaCpp.host}:\${toString config.lukasf.llamaCpp.port}/v1";
        description = "OpenAI-compatible llama.cpp base URL for Open WebUI.";
      };

      environment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Extra environment variables for Open WebUI.";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Environment file passed to the Open WebUI service.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Open the Open WebUI port in the firewall.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.llama-cpp = {
      enable = true;
      package = llamaPackage;
      inherit (cfg)
        host
        port
        modelsDir
        modelsPreset
        extraFlags
        openFirewall
        ;
    };

    services.open-webui = lib.mkIf cfg.ui.enable {
      enable = true;
      inherit (cfg.ui)
        package
        host
        port
        stateDir
        environmentFile
        openFirewall
        ;
      environment = {
        ENABLE_OLLAMA_API = "False";
        ENABLE_OPENAI_API = "True";
        OPENAI_API_BASE_URL = resolvedLlamaCppBaseUrl;
        OPENAI_API_BASE_URLS = resolvedLlamaCppBaseUrl;
        OPENAI_API_KEY = "sk-no-key-required";
        OPENAI_API_KEYS = "sk-no-key-required";
        DEFAULT_MODELS = cfg.defaultModel;
      }
      // cfg.ui.environment;
    };

    systemd.services.llama-cpp = lib.mkIf (!cfg.autoStart) {
      wantedBy = lib.mkForce [ ];
    };

    systemd.services.open-webui = lib.mkIf (cfg.ui.enable && !cfg.ui.autoStart) {
      wantedBy = lib.mkForce [ ];
    };
  };
}
