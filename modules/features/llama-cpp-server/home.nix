{
  config,
  lib,
  pkgs,
  ...
}:

# Local llama.cpp server for macOS, managed as a launchd user agent. Mirrors
# the NixOS lukasf.llamaCpp module (router mode, HF-downloaded GGUF presets,
# Ollama-compatible port) so clients keep one convention across hosts.
let
  cfg = config.lukasf.llamaCppServer;

  modelsPresetFile = pkgs.writeText "llama-models.ini" (lib.generators.toINI { } cfg.modelsPreset);

  logDir = "${config.xdg.stateHome}/llama-cpp";

  # Same presets as modules/features/llama-cpp-openwebui/nixos.nix; models
  # download from Hugging Face into ~/Library/Caches/llama.cpp on first use.
  defaultModelsPreset = {
    "qwen3-coder:30b" = {
      hf-repo = "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF";
      hf-file = "Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf";
      alias = "qwen3-coder:30b,qwen3-coder";
      # 64k so agentic opencode sessions don't hit the window; fit=on
      # shrinks it if the KV cache would not fit in memory.
      c = "65536";
      fit = "on";
      jinja = "on";
      temp = "0.2";
      top-p = "0.95";
      min-p = "0.01";
    };

    "qwen3.8:27b" = {
      hf-repo = "unsloth/Qwen3.8-27B-GGUF";
      hf-file = "Qwen3.8-27B-UD-Q4_K_M.gguf";
      alias = "qwen3.8:27b";
      c = "32768";
      fit = "on";
      jinja = "on";
    };

    "qwen3:8b" = {
      hf-repo = "Qwen/Qwen3-8B-GGUF";
      hf-file = "Qwen3-8B-Q4_K_M.gguf";
      alias = "qwen3:8b,qwen3-fast";
      c = "32768";
      fit = "on";
      jinja = "on";
    };
  };
in
{
  options.lukasf.llamaCppServer = {
    enable = lib.mkEnableOption "local llama.cpp server (launchd user agent)";

    package = lib.mkPackageOption pkgs "llama-cpp" { };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address llama-server binds to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "Port llama-server listens on (Ollama default for client compatibility).";
    };

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "qwen3-coder:30b";
      description = "Default model alias used by clients.";
    };

    modelsPreset = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = defaultModelsPreset;
      description = "llama-server router preset entries, rendered to INI.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      # No --parallel: llama-server splits the context between slots, and a
      # single local opencode user is better served by one slot with the
      # full window (requests over the per-slot limit trigger opencode's
      # compaction loop).
      default = [
        "--models-max"
        "1"
        "--cache-ram"
        "8192"
      ];
      description = "Extra flags passed to llama-server.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isDarwin;
        message = "lukasf.llamaCppServer targets macOS; use lukasf.llamaCpp (NixOS) elsewhere.";
      }
    ];

    home.packages = [ cfg.package ];

    launchd.agents.llama-cpp = {
      enable = true;
      config = {
        ProgramArguments = [
          (lib.getExe' cfg.package "llama-server")
          "--host"
          cfg.host
          "--port"
          (toString cfg.port)
          "--models-preset"
          (toString modelsPresetFile)
        ]
        ++ cfg.extraFlags;
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "${logDir}/llama-server.log";
        StandardErrorPath = "${logDir}/llama-server.err.log";
      };
    };

    home.activation.ensureLlamaCppLogDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${logDir}"
    '';
  };
}
