{
  config,
  lib,
  ...
}:

# X11 twin of the Sway session for streamed/headless desktops: Sway is
# Wayland-only and cannot run on the Xorg-dummy capture path, and this
# nixpkgs pin has no GNOME Xorg session anymore. The Home Manager side
# renders the SAME tiling definition as Sway, so the bindings match.
let
  cfg = config.desktop.i3;
in
{
  options.desktop.i3 = {
    enable = lib.mkEnableOption "i3 X11 session rendered from the shared tiling definition";
  };

  config = lib.mkIf cfg.enable {
    services.xserver.enable = lib.mkDefault true;
    services.xserver.windowManager.i3.enable = true;
    services.displayManager.defaultSession = lib.mkDefault "none+i3";
    # Same layouts as the other desktop modules.
    services.xserver.xkb.layout = lib.mkDefault "us,de";
  };
}
