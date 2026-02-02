{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.oh-my-opencode;
  configRoot = config.xdg.configHome or "${config.home.homeDirectory}/.config";
  opencodeConfigDir = "${configRoot}/opencode";
  packageVersion = if cfg.version == null then "latest" else cfg.version;
  packageSpecifier = "oh-my-opencode" + (if cfg.version == null then "" else "@${cfg.version}");

  installFlags = [
    "--no-tui"
    "--claude=${cfg.subscriptions.claude}"
    "--openai=${cfg.subscriptions.openai}"
    "--gemini=${cfg.subscriptions.gemini}"
    "--copilot=${cfg.subscriptions.copilot}"
    "--opencode-zen=${cfg.subscriptions.opencodeZen}"
    "--zai-coding-plan=${cfg.subscriptions.zaiCodingPlan}"
  ]
  ++ cfg.extraFlags;

  installCmd = "${pkgs.bun}/bin/bunx ${packageSpecifier} install ${lib.escapeShellArgs installFlags}";
in
{
  options.programs.oh-my-opencode = {
    enable = lib.mkEnableOption "Oh My OpenCode plugin installer (non-interactive)";

    version = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "3.1.10";
      description = "oh-my-opencode npm version to install (null follows upstream latest).";
      example = "3.1.10";
    };

    subscriptions = {
      claude = lib.mkOption {
        type = lib.types.enum [
          "yes"
          "no"
          "max20"
        ];
        default = "no";
        description = "Claude subscription flag for the installer.";
      };

      openai = lib.mkOption {
        type = lib.types.enum [
          "yes"
          "no"
        ];
        default = "no";
        description = "OpenAI/ChatGPT Plus availability flag.";
      };

      gemini = lib.mkOption {
        type = lib.types.enum [
          "yes"
          "no"
        ];
        default = "no";
        description = "Gemini access flag.";
      };

      copilot = lib.mkOption {
        type = lib.types.enum [
          "yes"
          "no"
        ];
        default = "no";
        description = "GitHub Copilot subscription flag.";
      };

      opencodeZen = lib.mkOption {
        type = lib.types.enum [
          "yes"
          "no"
        ];
        default = "no";
        description = "OpenCode Zen access flag.";
      };

      zaiCodingPlan = lib.mkOption {
        type = lib.types.enum [
          "yes"
          "no"
        ];
        default = "no";
        description = "Z.ai Coding Plan availability flag.";
      };
    };

    extraFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional flags passed to bunx oh-my-opencode install.";
      example = [ "--variant=high" ];
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.opencode
      pkgs.bun
    ];

    home.activation.ohMyOpenCodeInstall = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -euo pipefail
      config_dir="${opencodeConfigDir}"
      marker="$config_dir/.oh-my-opencode-installed"

      mkdir -p "$config_dir"

      current_version=""
      if [ -f "$marker" ]; then
        current_version="$(cat "$marker")"
      fi

      desired_version='${packageVersion}'

      if [ "$current_version" != "$desired_version" ]; then
        ${installCmd}
        echo "$desired_version" > "$marker"
      fi
    '';
  };
}
