{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.kustomize;
in
{
  options.ai.skills.kustomize = {
    enable = lib.mkEnableOption "Kustomize overlays skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/kustomize/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/kustomize/SKILL.md".source = ./SKILL.md;
  };
}
