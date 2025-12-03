{ pkgs, lib, ... }:

{
  home.packages = lib.mkAfter [
    pkgs.podman
    pkgs.btop
  ];

  dconf.settings."org/gnome/desktop/wm/keybindings" = {
    "switch-windows" = [ "<Alt>Tab" ];
    "switch-windows-backward" = [ "<Shift><Alt>Tab" ];
    "switch-applications" = [ ];
    "switch-applications-backward" = [ ];
  };
}
