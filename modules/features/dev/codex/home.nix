{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.programs.codex;
in
{
  config = lib.mkMerge [
    {
      # Disabled by default - opencode is the preferred AI coding agent
      programs.codex.enable = lib.mkDefault false;
    }
    (lib.mkIf cfg.enable {
      programs.codex.package = pkgs.codex;
    })
  ];
}
