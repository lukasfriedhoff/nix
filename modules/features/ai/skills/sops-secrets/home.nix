{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.sopsSecrets;
in
{
  options.ai.skills.sopsSecrets = {
    enable = lib.mkEnableOption "SOPS encryption and age key management skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/sops-secrets/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/sops-secrets/SKILL.md".source = ./SKILL.md;
  };
}
