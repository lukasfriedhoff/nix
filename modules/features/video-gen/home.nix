{
  config,
  lib,
  pkgs,
  ...
}:

# ComfyUI for on-demand video generation on macOS, managed as a launchd
# user agent. The agent never autostarts: this Mac runs one AI runtime at
# a time (llama-cpp-server owns the login session by default; both share
# 36 GB of unified memory), so video-start kickstarts the agent and
# video-stop kills it. See docs/services/video-gen.md.
let
  cfg = config.lukasf.videoGen;

  # The comfyui package patch defaults --base-directory to
  # $XDG_DATA_HOME/comfyui, which under Home Manager on macOS would be
  # ~/Library/Application Support/comfyui; pin the plain XDG default path
  # instead so the models tree lives in one place whether the agent or a
  # shell-launched `comfyui` is running.
  baseDir = "${config.home.homeDirectory}/.local/share/comfyui";
  modelsDir = "${baseDir}/models";
  logDir = "${config.xdg.stateHome}/comfyui";

  hfCli = lib.getExe' pkgs.python3Packages.huggingface-hub "hf";

  serverArgs = [
    (lib.getExe cfg.package)
    "--base-directory"
    baseDir
    "--listen"
    cfg.host
    "--port"
    (toString cfg.port)
  ]
  ++ cfg.extraFlags;

  # video-pull [preset]: fetch a preset's weights with the standalone HF
  # CLI (resumable, token-aware) and link them into the models tree.
  # ComfyUI's in-UI downloader is avoided: it hangs when a CDN drops a
  # connection, the same reason llama-pull exists.
  presetCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: preset: ''
      ${lib.escapeShellArg name})
        ${lib.concatStringsSep "\n" (
          f: "  pull ${lib.escapeShellArg f.repo} ${lib.escapeShellArg f.file} ${lib.escapeShellArg f.dir}"
        ) preset.files}
        ;;
    '') cfg.modelsPreset
  );

  pullScript = pkgs.writeShellScriptBin "video-pull" ''
    set -euo pipefail
    preset="''${1:-${cfg.defaultPreset}}"
    ${lib.optionalString (cfg.hfTokenFile != null) ''
      if [ -r "${cfg.hfTokenFile}" ]; then
        HF_TOKEN="$(cat "${cfg.hfTokenFile}")"
        export HF_TOKEN
      fi
    ''}
    export HF_HUB_DOWNLOAD_TIMEOUT=30
    base=${lib.escapeShellArg baseDir}
    pull() {
      local repo="$1" file="$2" dir="$3" name link path
      name="''${file##*/}"
      link="$base/models/$dir/$name"
      echo "pulling $repo/$file into $dir/$name (resumable; re-run if it stalls)" >&2
      # hf prints the local path, in recent versions prefixed with "path=".
      path="$(${hfCli} download "$repo" "$file" | tail -n 1)"
      path="''${path#path=}"
      mkdir -p "$(dirname "$link")"
      ln -sfn "$path" "$link"
      echo "linked: $link" >&2
    }
    case "$preset" in
      ${presetCases}
      *) echo "unknown preset '$preset'; known: ${lib.concatStringsSep " " (lib.attrNames cfg.modelsPreset)}" >&2; exit 1 ;;
    esac
  '';

  # First and only pull preset for now: Wan 2.2 TI2V-5B (text- and
  # image-to-video), all three fp16 files from the official Comfy-Org
  # repackage (verified against the repo 2026-11-07): 10.0 + 11.37 +
  # 1.41 GB, inside the ~28 GB Metal budget this Mac shares with
  # llama-server. FP8 repackagings exist but do not run on MPS.
  defaultModelsPreset = {
    "wan2.2:5b" = {
      files = [
        {
          repo = "Comfy-Org/Wan-2.2";
          file = "split_files/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors";
          dir = "diffusion_models";
        }
        {
          repo = "Comfy-Org/Wan-2.2";
          file = "split_files/text_encoders/umt5_xxl_fp16.safetensors";
          dir = "text_encoders";
        }
        {
          repo = "Comfy-Org/Wan-2.2";
          file = "split_files/vae/wan2.2_vae.safetensors";
          dir = "vae";
        }
      ];
    };
  };
in
{
  options.lukasf.videoGen = {
    enable = lib.mkEnableOption "ComfyUI video server (launchd user agent, on demand)";

    # No default on purpose: stable nixpkgs (26.05) does not package
    # ComfyUI for aarch64-darwin, and lib.mkPackageOption would still
    # force its default (a bare package-set lookup) even though the host
    # overrides it. The host picks the input that carries the package:
    # on work-mbp-01 the same pinned nixpkgs-unstable as the llama.cpp
    # override, both need fresh PyTorch Metal for the M5.
    package = lib.mkOption {
      type = lib.types.package;
      description = "The ComfyUI package to run (e.g. nixpkgs-unstable.legacyPackages.<system>.comfyui).";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address ComfyUI binds to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8188;
      description = "Port ComfyUI listens on (its default; the tux reverse tunnel forwards it).";
    };

    defaultPreset = lib.mkOption {
      type = lib.types.str;
      default = "wan2.2:5b";
      description = "Preset video-pull uses without an argument.";
    };

    modelsPreset = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            files = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    repo = lib.mkOption {
                      type = lib.types.str;
                      description = "Hugging Face repo id.";
                    };
                    file = lib.mkOption {
                      type = lib.types.str;
                      description = "File path within the repo.";
                    };
                    dir = lib.mkOption {
                      type = lib.types.str;
                      description = "Subdirectory under the ComfyUI models dir (e.g. diffusion_models, vae, text_encoders).";
                    };
                  };
                }
              );
              default = [ ];
              description = "Weight files the preset pulls and links into the models tree.";
            };
          };
        }
      );
      default = defaultModelsPreset;
      description = "Presets for video-pull: name -> { files = [ { repo, file, dir } ]; }.";
    };

    hfTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "File with a Hugging Face token exported as HF_TOKEN for preset downloads.";
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra flags passed to ComfyUI.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isDarwin;
        message = "lukasf.videoGen targets macOS; ComfyUI is not packaged for other systems in this flake.";
      }
    ];

    home.packages = [
      cfg.package
      pullScript
    ];

    # On demand by design: RunAtLoad/KeepAlive stay off, see the header.
    launchd.agents.comfyui = {
      enable = true;
      config = {
        ProgramArguments = serverArgs;
        KeepAlive = false;
        RunAtLoad = false;
        StandardOutPath = "${logDir}/comfyui.log";
        StandardErrorPath = "${logDir}/comfyui.err.log";
      };
    };

    home.activation.ensureVideoGenDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "${logDir}" "${modelsDir}"
    '';

    programs.bash.shellAliases = {
      video-start = "launchctl kickstart gui/$(id -u)/org.nix-community.home.comfyui";
      video-stop = "launchctl kill SIGTERM gui/$(id -u)/org.nix-community.home.comfyui";
      video-logs = "tail -f ${logDir}/comfyui.err.log";
    };
  };
}
