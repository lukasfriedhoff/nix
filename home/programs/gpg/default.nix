{ pkgs, ... }:
{
  programs.gpg = {
    enable = true;
  };
  services.gpg-agent = {
    enable = true;
    # pick ONE:
    pinentry.package = pkgs.pinentry-curses; # TUI
    # pinentryPackage = pkgs.pinentry-tty;
  };
}
