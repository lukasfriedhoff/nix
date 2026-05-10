{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.certManager;
in
{
  options.ai.skills.certManager = {
    enable = lib.mkEnableOption "cert-manager certificate management skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/cert-manager/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/cert-manager/SKILL.md".source = ./SKILL.md;
  };
}
