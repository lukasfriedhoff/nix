{
  config,
  lib,
  pkgs,
  ...
}:

# Declarative oh-my-opencode setup. The upstream `bunx oh-my-opencode
# install` wizard only adds the plugin to opencode.json and writes an
# oh-my-opencode.json with agent/category model routing - but it cannot edit
# the Home Manager-managed opencode.json (read-only store symlink), so both
# files are generated here instead. OpenCode installs plugins listed in its
# config by itself on startup.
let
  cfg = config.programs.oh-my-opencode;

  agentNames = [
    "sisyphus"
    "oracle"
    "librarian"
    "explore"
    "multimodal-looker"
    "prometheus"
    "metis"
    "momus"
    "atlas"
  ];

  categoryNames = [
    "visual-engineering"
    "ultrabrain"
    "deep"
    "artistry"
    "quick"
    "unspecified-low"
    "unspecified-high"
    "writing"
  ];

  modelRouting = lib.optionalAttrs (cfg.agentModel != null) {
    agents = lib.genAttrs agentNames (_: {
      model = cfg.agentModel;
    });
    categories = lib.genAttrs categoryNames (_: {
      model = cfg.agentModel;
    });
  };

  settings = lib.recursiveUpdate (
    {
      "$schema" =
        "https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/master/assets/oh-my-opencode.schema.json";
    }
    // modelRouting
  ) cfg.extraSettings;
in
{
  options.programs.oh-my-opencode = {
    enable = lib.mkEnableOption "oh-my-opencode opencode plugin (declarative)";

    version = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "3.1.10";
      description = "oh-my-opencode npm version pinned in the plugin entry (null follows latest).";
      example = "3.1.10";
    };

    agentModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        opencode model (provider/model) all oh-my-opencode agents and
        categories route to. null leaves the plugin's own defaults, which
        assume hosted providers.
      '';
      example = "llama-cpp/qwen3-coder:30b";
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Extra oh-my-opencode.json settings merged over the generated routing.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.opencode
      pkgs.bun
    ];

    programs.opencode.settings.plugin = [
      ("oh-my-opencode" + lib.optionalString (cfg.version != null) "@${cfg.version}")
    ];

    xdg.configFile."opencode/oh-my-opencode.json".text = builtins.toJSON settings;
  };
}
