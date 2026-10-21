# Remote-access clients for the work Mac: Royal TSX (RDP/VNC/SSH management)
# and Microsoft Windows App (Remote Desktop / Windows 365). Both are closed
# source and come from pkgs/ (vendor artifacts pinned to the Homebrew cask
# versions); mac-app-util links them into ~/Applications/Home Manager Apps.
{
  config,
  lib,
  pkgs,
  workSystem ? false,
  ...
}:
let
  cfg = config.programs."remote-access-tools";
in
{
  options.programs."remote-access-tools" = {
    enable = lib.mkEnableOption "Royal TSX and Microsoft Windows App";
  };

  config = lib.mkMerge [
    {
      programs."remote-access-tools".enable = lib.mkDefault (workSystem && pkgs.stdenv.isDarwin);
    }
    (lib.mkIf cfg.enable {
      home.packages = [
        pkgs.royal-tsx
        pkgs.windows-app
      ];
    })
  ];
}
