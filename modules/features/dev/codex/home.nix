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
      programs.codex.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      programs.codex.package = pkgs.codex;
    })
  ];
}
