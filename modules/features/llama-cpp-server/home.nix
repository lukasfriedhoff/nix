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

  serverArgs = [
    (lib.getExe' cfg.package "llama-server")
    "--host"
    cfg.host
    "--port"
    (toString cfg.port)
    "--models-preset"
    (toString modelsPresetFile)
  ]
  ++ cfg.extraFlags;

  # launchd cannot read a token file into the environment itself.
  serverWrapper = pkgs.writeShellScript "llama-server-wrapper" ''
    ${lib.optionalString (cfg.hfTokenFile != null) ''
      if [ -r "${cfg.hfTokenFile}" ]; then
        HF_TOKEN="$(cat "${cfg.hfTokenFile}")"
        export HF_TOKEN
      fi
    ''}
    exec ${lib.escapeShellArgs serverArgs}
  '';

  # llama-pull [preset]: fetch a preset's GGUF with the standalone HF CLI
  # (resumable, token-aware) instead of llama-server's in-process download,
  # which hangs when the CDN drops a connection.
  hfCli = lib.getExe' pkgs.python3Packages.huggingface-hub "hf";
  presetCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: preset:
      "${lib.escapeShellArg name}) repo=${lib.escapeShellArg preset.hf-repo}; file=${lib.escapeShellArg preset.hf-file} ;;"
    ) (lib.filterAttrs (_: p: p ? hf-repo && p ? hf-file) cfg.modelsPreset)
  );
  pullScript = pkgs.writeShellScriptBin "llama-pull" ''
    set -euo pipefail
    preset="''${1:-${cfg.defaultModel}}"
    case "$preset" in
      ${presetCases}
      *) echo "unknown preset '$preset'; known: ${lib.concatStringsSep " " (lib.attrNames cfg.modelsPreset)}" >&2; exit 1 ;;
    esac
    ${lib.optionalString (cfg.hfTokenFile != null) ''
      if [ -r "${cfg.hfTokenFile}" ]; then
        HF_TOKEN="$(cat "${cfg.hfTokenFile}")"
        export HF_TOKEN
      fi
    ''}
    export HF_HUB_DOWNLOAD_TIMEOUT=30
    echo "pulling $repo/$file into ~/.cache/huggingface (resumable; re-run if it stalls)" >&2
    exec ${hfCli} download "$repo" "$file"
  '';

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
      c = "65536";
      fit = "on";
      jinja = "on";
    };

    "qwen3:8b" = {
      hf-repo = "Qwen/Qwen3-8B-GGUF";
      hf-file = "Qwen3-8B-Q4_K_M.gguf";
      alias = "qwen3:8b,qwen3-fast";
      c = "65536";
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

    hfTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "File with a Hugging Face token exported as HF_TOKEN for preset downloads.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start llama-server at login and keep it alive; false leaves it to llama-start.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      # --parallel 1: without it llama-server auto-creates 4 slots sharing
      # one unified KV cache of the preset window, so a few concurrent agent
      # requests (oh-my-opencode fans out, tux adds more over the tunnel)
      # exhaust it and every one of them fails with "Context size has been
      # exceeded". One slot keeps the full window; extra requests queue.
      default = [
        "--models-max"
        "1"
        "--cache-ram"
        "8192"
        "--parallel"
        "1"
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

    home.packages = [
      cfg.package
      pullScript
    ];

    launchd.agents.llama-cpp = {
      enable = true;
      config = {
        ProgramArguments = [ "${serverWrapper}" ];
        KeepAlive = cfg.autoStart;
        RunAtLoad = cfg.autoStart;
        StandardOutPath = "${logDir}/llama-server.log";
        StandardErrorPath = "${logDir}/llama-server.err.log";
      };
    };

    home.activation.ensureLlamaCppLogDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${logDir}"
    '';

    programs.bash.shellAliases = {
      llama-start = "launchctl kickstart gui/$(id -u)/org.nix-community.home.llama-cpp";
      llama-stop = "launchctl kill SIGTERM gui/$(id -u)/org.nix-community.home.llama-cpp";
      llama-logs = "tail -f ${logDir}/llama-server.err.log";
      # Throughput lives in the stdout log: prefill tok/s per chunk, then
      # 'tg = N t/s' for generation.
      llama-stats = "tail -f ${logDir}/llama-server.log | grep --line-buffered -E 'tokens per second|tg = |send_error'";
    };
  };
}
