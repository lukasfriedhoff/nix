{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.flake;
in
{
  options.ai.skills.flake = {
    enable = lib.mkEnableOption "Nix flake structure and patterns skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/flake/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/flake/SKILL.md".source = ./SKILL.md;
  };
}
