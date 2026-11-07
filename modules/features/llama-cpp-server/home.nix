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

  # The four models kept after benchmarking eleven candidates on work-mbp-01
  # (M5 Max, 36 GB, llama.cpp 0.6.0, Q4, 2026-10-30; numbers and the rest of
  # the field in docs/services/local-llm.md). Weights are read from the
  # Hugging Face hub cache (~/.cache/huggingface/hub, filled by llama-pull);
  # llama-server downloads anything missing on first use.
  defaultModelsPreset =
    let
      common = {
        # 64k so agentic opencode sessions don't hit the window; fit=on
        # shrinks it if the KV cache would not fit in memory.
        c = "65536";
        fit = "on";
        jinja = "on";
        # Text-only: the repos ship a vision projector next to the weights;
        # skipping it saves its download and about 1 GB of unified memory.
        mmproj-auto = "off";
      };
      qwen36 = {
        hf-repo = "unsloth/Qwen3.6-35B-A3B-GGUF";
        hf-file = "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf";
      };
    in
    {
      # Daily driver for opencode: 3B-active MoE, 92 tok/s decode and still 81
      # at 16k context. Thinking is off here because with it on a trivial task
      # spent 7-12k tokens; the -think preset below keeps it for hard problems.
      # Sampling per the Qwen model card for the respective mode.
      "qwen3.6:35b" =
        common
        // qwen36
        // {
          alias = "qwen3.6:35b,qwen3.6";
          reasoning = "off";
          temp = "0.7";
          top-p = "0.8";
          top-k = "20";
          min-p = "0.0";
        };

      "qwen3.6:35b-think" =
        common
        // qwen36
        // {
          alias = "qwen3.6:35b-think,qwen3.6-think";
          temp = "0.6";
          top-p = "0.95";
          top-k = "20";
          min-p = "0.0";
        };

      # Quality pick: dense 27B at ~23 tok/s. Medium effort keeps a small task
      # around 2k tokens; the template default thinks far longer.
      "qwen3.8:27b" = common // {
        hf-repo = "unsloth/Qwen3.8-27B-GGUF";
        hf-file = "Qwen3.8-27B-UD-Q4_K_M.gguf";
        alias = "qwen3.8:27b,qwen3.8";
        reasoning-effort = "medium";
        temp = "1.0";
        top-p = "0.95";
        top-k = "20";
        min-p = "0.0";
      };

      # Quick answers: smallest file (11 GiB), 126 tok/s, clean tool calls.
      "gpt-oss:20b" = common // {
        hf-repo = "ggml-org/gpt-oss-20b-GGUF";
        hf-file = "gpt-oss-20b-MXFP4.gguf";
        alias = "gpt-oss:20b,gpt-oss";
        reasoning-effort = "medium";
        temp = "1.0";
        top-p = "1.0";
      };

      # Second opinion from another model family: 4B-active MoE, 88 tok/s.
      "gemma4:26b" = common // {
        hf-repo = "unsloth/gemma-4-26B-A4B-it-GGUF";
        hf-file = "gemma-4-26B-A4B-it-UD-Q4_K_M.gguf";
        alias = "gemma4:26b,gemma4";
        temp = "1.0";
        top-p = "0.95";
        top-k = "64";
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
      default = "qwen3.6:35b";
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
