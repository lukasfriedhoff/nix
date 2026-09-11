{
  config,
  lib,
  pkgs,
  ...
}:

# MLX runtime for Apple silicon, served over an OpenAI-compatible API by
# mlx_lm.server on demand (no login autostart; mlx-start / mlx-stop).
#
# nixpkgs' mlx is built with MLX_BUILD_METAL=false (Apple's Metal shader
# compiler cannot run in the sandbox), which makes it CPU-only and useless
# for LLMs. The Metal-enabled runtime therefore comes from Apple's official
# PyPI wheels, installed into a uv-managed venv by an activation step. That
# part is impure by necessity: pinned here, downloaded at activation.
let
  cfg = config.lukasf.mlxLm;

  logDir = "${config.xdg.stateHome}/mlx-lm";
  agentLabel = "org.nix-community.home.mlx-lm";
  venv = cfg.venvDir;
  specs = lib.concatStringsSep " " (
    lib.mapAttrsToList (name: version: lib.escapeShellArg "${name}==${version}") cfg.pypiVersions
  );

  readToken = lib.optionalString (cfg.hfTokenFile != null) ''
    if [ -r "${cfg.hfTokenFile}" ]; then
      HF_TOKEN="$(cat "${cfg.hfTokenFile}")"
      export HF_TOKEN
    fi
  '';

  serverArgs = [
    "${venv}/bin/mlx_lm.server"
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
    ${readToken}
    exec ${lib.escapeShellArgs serverArgs}
  '';

  # Pre-download with the standalone HF CLI (resumable); the in-server
  # downloader hangs when the CDN drops a connection mid-transfer.
  pullScript = pkgs.writeShellScriptBin "mlx-pull" ''
    set -euo pipefail
    repo="''${1:-${cfg.model}}"
    ${readToken}
    export HF_HUB_DOWNLOAD_TIMEOUT=30
    echo "pulling $repo into ~/.cache/huggingface (resumable; re-run if it stalls)" >&2
    exec ${venv}/bin/hf download "$repo"
  '';
in
{
  options.lukasf.mlxLm = {
    enable = lib.mkEnableOption "mlx-lm server (on demand, Apple silicon, PyPI Metal wheels)";

    python = lib.mkPackageOption pkgs "python3" { };

    venvDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.dataHome}/mlx-lm/venv";
      defaultText = lib.literalExpression ''"''${config.xdg.dataHome}/mlx-lm/venv"'';
      description = "uv-managed virtualenv holding the Metal-enabled mlx wheels.";
    };

    pypiVersions = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        mlx = "0.32.2";
        mlx-lm = "0.31.3";
      };
      description = "Exact PyPI versions installed into the venv (changing them reinstalls).";
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

    home.packages = [
      pkgs.uv
      pullScript
    ];

    # (Re)create the venv when missing or when the pinned versions change.
    # Needs network; a failed install only warns so activation still completes.
    home.activation.installMlxVenv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      stamp="${venv}/.nix-mlx-versions"
      want=${lib.escapeShellArg specs}
      if [ ! -x "${venv}/bin/mlx_lm.server" ] || [ "$(cat "$stamp" 2>/dev/null)" != "$want" ]; then
        echo "mlx-lm: installing Metal wheels into ${venv} ($want)"
        if ${pkgs.uv}/bin/uv venv -q --python ${cfg.python}/bin/python3 "${venv}" \
           && ${pkgs.uv}/bin/uv pip install -q --python "${venv}/bin/python" ${specs}; then
          printf '%s' "$want" > "$stamp"
        else
          echo "mlx-lm: venv install failed (offline?) - rerun the switch when online" >&2
        fi
      fi
      mkdir -p "${logDir}"
    '';

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

    programs.bash.shellAliases = {
      mlx-start = "launchctl kickstart gui/$(id -u)/${agentLabel}";
      mlx-stop = "launchctl kill SIGTERM gui/$(id -u)/${agentLabel}";
      mlx-logs = "tail -f ${logDir}/mlx-lm.err.log";
    };
  };
}
