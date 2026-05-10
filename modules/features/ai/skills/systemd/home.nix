{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.systemd;
in
{
  options.ai.skills.systemd = {
    enable = lib.mkEnableOption "Systemd services and timers skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/systemd/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/systemd/SKILL.md".source = ./SKILL.md;
  };
}
