{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.cilium;
in
{
  options.ai.skills.cilium = {
    enable = lib.mkEnableOption "Cilium networking skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/cilium/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/cilium/SKILL.md".source = ./SKILL.md;
  };
}
