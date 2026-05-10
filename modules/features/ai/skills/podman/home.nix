{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.podman;
in
{
  options.ai.skills.podman = {
    enable = lib.mkEnableOption "Podman container management skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/podman/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/podman/SKILL.md".source = ./SKILL.md;
  };
}
