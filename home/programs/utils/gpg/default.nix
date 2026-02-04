{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.programs.gpg;
in
{
  config = lib.mkMerge [
    {
      programs.gpg.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      services.gpg-agent = {
        enable = lib.mkDefault true;
        # pick ONE:
        pinentry.package = pkgs.pinentry-curses; # TUI
        # pinentryPackage = pkgs.pinentry-tty;
      };
    })
  ];
}
