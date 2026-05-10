{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.helm;
in
{
  options.ai.skills.helm = {
    enable = lib.mkEnableOption "Helm charts and values skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/helm/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/helm/SKILL.md".source = ./SKILL.md;
  };
}
