{
  config,
  inputs,
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
  options.desktop.libreoffice = {
    enable = lib.mkEnableOption "LibreOffice office suite";

    package = lib.mkOption {
      type = lib.types.package;
      # The root nixpkgs (1f607aa, 2026-10-25) cannot build LibreOffice: its
      # binutils 2.46 assembler aborts with "elf.c:3571 assertion fail" on
      # xmloff, and Hydra has no binary either, so every Linux desktop
      # rebuild failed (tux, 2026-11-07). The pinned nixpkgs-unstable ships a
      # cached 26.8.0.3. Return to pkgs.libreoffice once the root nixpkgs
      # moves past the fix.
      default = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.libreoffice;
      defaultText = lib.literalExpression "inputs.nixpkgs-unstable.legacyPackages.\${system}.libreoffice";
      description = "LibreOffice package to wrap with the light GTK theme.";
    };
  };

  config =
    let
      # LibreOffice renders spreadsheets with dark backgrounds when the global
      # theme is dark, which makes text illegible. Force a light GTK theme for
      # every entry point by wrapping the shipped binaries.
      libreOfficeLight = pkgs.symlinkJoin {
        name = "libreoffice-light";
        paths = [ cfg.package ];
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
