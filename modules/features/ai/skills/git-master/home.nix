{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.gitMaster;
in
{
  options.ai.skills.gitMaster = {
    enable = lib.mkEnableOption "Git operations and branch strategy skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/git-master/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/git-master/SKILL.md".source = ./SKILL.md;
  };
}
