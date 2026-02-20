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
  autoEnable = profile != null && lib.elem profile personalDesktopProfiles;
in
{
  options.desktop.libreoffice.enable = lib.mkEnableOption "LibreOffice office suite";

  config =
    let
      # LibreOffice renders spreadsheets with dark backgrounds when the global
      # theme is dark, which makes text illegible. Force a light GTK theme for
      # every entry point by wrapping the shipped binaries.
      libreOfficeLight = pkgs.symlinkJoin {
        name = "libreoffice-light";
        paths = [ pkgs.libreoffice ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          for exe in "$out"/bin/*; do
            if [ -x "$exe" ] && [ ! -d "$exe" ]; then
              wrapProgram "$exe" \
                --set GTK_THEME Adwaita:light \
                --set SAL_FORCE_HC 0 \
                --set SAL_USE_VCLPLUGIN gtk3
            fi
          done
        '';
      };
    in
    lib.mkMerge [
      (lib.mkIf autoEnable {
        desktop.libreoffice.enable = lib.mkDefault true;
      })
      (lib.mkIf cfg.enable {
        environment.systemPackages = [ libreOfficeLight ];
      })
    ];
}
