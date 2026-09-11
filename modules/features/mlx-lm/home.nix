{
  config,
  lib,
  pkgs,
  ...
}:

# MLX runtime for Apple silicon: serves MLX-quantized models over an
# OpenAI-compatible API via mlx_lm.server. Complements lukasf.llamaCppServer
# (GGUF); models download from Hugging Face into ~/.cache/huggingface.
# The launchd agent exists only for supervision - it does NOT start at
# login; use mlx-start / mlx-stop (docs/services/local-llm.md).
let
  cfg = config.lukasf.mlxLm;

  logDir = "${config.xdg.stateHome}/mlx-lm";
  agentLabel = "org.nix-community.home.mlx-lm";

  serverArgs = [
    "${cfg.package}/bin/mlx_lm.server"
    "--host"
    cfg.host
    "--port"
    (toString cfg.port)
    "--model"
    cfg.model
  ]
  ++ cfg.extraFlags;

  # launchd cannot read a token file into the environment itself.
  serverWrapper = pkgs.writeShellScript "mlx-lm-server" ''
    ${lib.optionalString (cfg.hfTokenFile != null) ''
      if [ -r "${cfg.hfTokenFile}" ]; then
        HF_TOKEN="$(cat "${cfg.hfTokenFile}")"
        export HF_TOKEN
      fi
    ''}
    exec ${lib.escapeShellArgs serverArgs}
  '';
in
{
  options.lukasf.mlxLm = {
    enable = lib.mkEnableOption "mlx-lm server (on demand, Apple silicon)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.python3.withPackages (ps: [ ps.mlx-lm ]);
      defaultText = lib.literalExpression "pkgs.python3.withPackages (ps: [ ps.mlx-lm ])";
      description = "Python environment providing mlx_lm.server.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address mlx_lm.server binds to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11435;
      description = "Port mlx_lm.server listens on (llama.cpp owns 11434).";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit";
      description = "Hugging Face repo of the MLX-quantized default model.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra flags passed to mlx_lm.server.";
    };

    hfTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        File containing a Hugging Face access token, exported as HF_TOKEN
        for model downloads. Anonymous downloads are rate-limited per IP
        and stall on multi-GB models.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isDarwin;
        message = "lukasf.mlxLm requires Apple silicon macOS.";
      }
    ];

    # cfg.package is intentionally NOT in home.packages. macOS must expose
    # exactly one python3 store path to buildEnv, so the mlx-lm runtime
    # reaches PATH via the platform/macos/home.nix env instead. The launchd
    # agent below references cfg.package by absolute path, so the agent
    # works without mlx-lm on PATH.

    launchd.agents.mlx-lm = {
      enable = true;
      config = {
        ProgramArguments = [ "${serverWrapper}" ];
        RunAtLoad = false;
        KeepAlive = false;
        ProcessType = "Interactive";
        StandardOutPath = "${logDir}/mlx-lm.log";
        StandardErrorPath = "${logDir}/mlx-lm.err.log";
      };
    };

    home.activation.ensureMlxLmLogDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${logDir}"
    '';

    programs.bash.shellAliases = {
      mlx-start = "launchctl kickstart gui/$(id -u)/${agentLabel}";
      mlx-stop = "launchctl kill SIGTERM gui/$(id -u)/${agentLabel}";
      mlx-logs = "tail -f ${logDir}/mlx-lm.err.log";
    };
  };
}
