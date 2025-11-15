{
  config,
  lib,
  pkgs,
  profile ? null,
  ...
}:

let
  cfg = config.desktop.libreoffice;
  personalDesktopProfiles = [
    "srv4"
    "tux"
    "tab"
  ];
  autoEnable =
    profile != null
    && lib.elem profile personalDesktopProfiles;
in
{
  options.desktop.libreoffice.enable = lib.mkEnableOption "LibreOffice office suite";

  config = lib.mkMerge [
    (lib.mkIf autoEnable {
      desktop.libreoffice.enable = lib.mkDefault true;
    })
    (lib.mkIf cfg.enable {
      environment.systemPackages = [
        pkgs.libreoffice
      ];
    })
  ];
}
