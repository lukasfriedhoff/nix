{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.flux;
in
{
  options.ai.skills.flux = {
    enable = lib.mkEnableOption "Flux GitOps skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/flux/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/flux/SKILL.md".source = ./SKILL.md;
  };
}
