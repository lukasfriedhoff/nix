{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.programs.lazygit;
in
{
  config = lib.mkMerge [
    {
      programs.lazygit.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      programs.lazygit.package = pkgs.lazygit;
    })
  ];
}
