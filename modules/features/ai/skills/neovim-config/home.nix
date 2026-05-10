{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.neovimConfig;
in
{
  options.ai.skills.neovimConfig = {
    enable = lib.mkEnableOption "Neovim Lua and Nix configuration skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/neovim-config/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/neovim-config/SKILL.md".source = ./SKILL.md;
  };
}
