{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.kubernetes;
in
{
  options.ai.skills.kubernetes = {
    enable = lib.mkEnableOption "Kubernetes resources and kubectl operations skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/kubernetes/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/kubernetes/SKILL.md".source = ./SKILL.md;
  };
}
