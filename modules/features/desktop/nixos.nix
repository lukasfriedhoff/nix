# Desktop environment aggregation module
# Enables common desktop features with a single option
{
  config,
  lib,
  ...
}:

let
  cfg = config.desktop;
in
{
  options.desktop = {
    enable = lib.mkEnableOption "desktop environment with common features";
  };

  config = lib.mkIf cfg.enable {
    # Auto-enable common desktop features
    # Each can be individually overridden with lib.mkForce false
    desktop.gnome.enable = lib.mkDefault true;
    desktop.laptop.enable = lib.mkDefault true;
    desktop.libreoffice.enable = lib.mkDefault true;
    desktop.gaming.enable = lib.mkDefault true;

    # Enable pipewire audio
    lukasf.pipewire.enable = lib.mkDefault true;
  };
}
