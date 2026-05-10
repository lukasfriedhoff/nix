{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.skills.wireguard;
in
{
  options.ai.skills.wireguard = {
    enable = lib.mkEnableOption "WireGuard VPN configuration skill";
  };

  config = lib.mkIf cfg.enable {
    home.file.".claude/skills/wireguard/SKILL.md".source = ./SKILL.md;
    home.file.".opencode/skills/wireguard/SKILL.md".source = ./SKILL.md;
  };
}
