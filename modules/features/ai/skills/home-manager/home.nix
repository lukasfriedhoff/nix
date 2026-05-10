{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.homeManager;
in
{
  options.ai.skills.homeManager = {
    enable = lib.mkEnableOption "Home Manager module patterns skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/home-manager/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/home-manager/SKILL.md".source = ./SKILL.md;
  };
}
