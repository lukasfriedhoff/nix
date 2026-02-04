{
  config,
  lib,
  pkgs,
  profile ? null,
  ...
}:

let
  personalDesktopProfiles = [
    "srv4"
    "tux"
    "tab"
  ];
  isPersonalDesktop = profile != null && lib.elem profile personalDesktopProfiles;
  isLinuxDesktop = isPersonalDesktop && (!pkgs.stdenv.isDarwin);
in
{
  config = lib.mkIf isLinuxDesktop {
    programs.evolution.enable = lib.mkDefault true;
    programs.evolution.nextcloud.enable = lib.mkDefault true;

    programs.moonlight.enable = lib.mkDefault true;

    home.packages = [ pkgs.gpodder ];
  };
}
