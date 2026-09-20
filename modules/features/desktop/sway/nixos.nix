# Sway tiling Wayland session, installed alongside the primary desktop.
# GDM lists it as an additional session, so GNOME stays available as a
# fallback at every login. Keybindings mirror the AeroSpace setup on
# macOS via modules/features/desktop/tiling/def.nix.
{
  config,
  lib,
  pkgs,
  linuxUser,
  ...
}:
let
  cfg = config.desktop.sway;
in
{
  options.desktop.sway = {
    enable = lib.mkEnableOption "Sway tiling Wayland session alongside the primary desktop";
    modifier = lib.mkOption {
      type = lib.types.enum [
        "super"
        "alt"
      ];
      default = "super";
      description = ''
        Logical modifier for the shared tiling bindings. "super" avoids
        collisions with in-app Alt shortcuts on Linux; "alt" matches the
        AeroSpace muscle memory exactly.
      '';
    };
    nvidiaUnsupportedGpu = lib.mkEnableOption "pass --unsupported-gpu on NVIDIA-rendered hosts";
  };

  config = lib.mkIf cfg.enable {
    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
      extraOptions = lib.optional cfg.nvidiaUnsupportedGpu "--unsupported-gpu";
    };

    # Chromium/Electron only run as native Wayland clients when this is set —
    # the nixpkgs wrapper gates --ozone-platform-hint on it. Under XWayland
    # they cannot use keyboard-shortcuts-inhibit, so a remote desktop in the
    # browser never receives Super+<key>: sway matches its own binding first
    # and the page sees nothing (see the --inhibited escape binding in
    # ./home.nix). Also fixes fractional scaling and IME in those apps.
    environment.sessionVariables.NIXOS_OZONE_WL = "1";

    # swaylock authenticates through PAM; without this entry unlocking fails.
    security.pam.services.swaylock = { };

    # swayosd writes the backlight through sysfs, not logind; its udev rule
    # grants that to the video group.
    services.udev.packages = [ pkgs.swayosd ];
    users.users.${linuxUser}.extraGroups = lib.mkAfter [ "video" ];

    # Screen sharing under wlroots; GNOME's portal keeps serving its own session.
    xdg.portal = {
      enable = lib.mkDefault true;
      extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
    };
  };
}
