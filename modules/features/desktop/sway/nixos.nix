# Sway tiling Wayland session, installed alongside the primary desktop.
# GDM lists it as an additional session, so GNOME stays available as a
# fallback at every login. Keybindings mirror the AeroSpace setup on
# macOS via modules/features/desktop/tiling/def.nix.
{
  config,
  lib,
  pkgs,
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

    # swaylock authenticates through PAM; without this entry unlocking fails.
    security.pam.services.swaylock = { };

    # Screen sharing under wlroots; GNOME's portal keeps serving its own session.
    xdg.portal = {
      enable = lib.mkDefault true;
      extraPortals = [ pkgs.xdg-desktop-portal-wlr ];
    };
  };
}
