{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.ssh;
in
{
  options.ai.skills.ssh = {
    enable = lib.mkEnableOption "SSH configuration skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/ssh/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/ssh/SKILL.md".source = ./SKILL.md;
  };
}
