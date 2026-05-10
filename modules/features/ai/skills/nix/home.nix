{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.nix;
in
{
  options.ai.skills.nix = {
    enable = lib.mkEnableOption "Nix development patterns skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/nix/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/nix/SKILL.md".source = ./SKILL.md;
  };
}
