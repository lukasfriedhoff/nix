{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.programs.chromium;
in
{
  config = lib.mkMerge [
    {
      programs.chromium.enable = lib.mkDefault (!pkgs.stdenv.isDarwin);
    }
    (lib.mkIf (cfg.enable && !pkgs.stdenv.isDarwin) {
      programs.chromium = {
        package = pkgs.chromium;
        # Installed through the ExtensionInstallForcelist policy, so each id
        # must still be served by the web store — an unavailable one fails
        # silently, with no extension and no error anywhere.
        extensions = [
          {
            # uBlock Origin *Lite* (MV3). Not the classic uBlock Origin:
            # that one is Manifest V2, and the store now answers its update
            # request with 204 (nothing to serve), so it had been installing
            # nothing here. Lite is the maintained MV3 build — filtering is
            # declarative, so it is weaker than full uBO on cosmetic and
            # scriptlet rules. Firefox still carries the full version.
            id = "ddkjiahejlhfcafbddmgiahcphecmpfh";
            updateUrl = "https://clients2.google.com/service/update2/crx";
          }
          {
            # I still don't care about cookies — dismisses consent banners.
            id = "fihnjjcciajhdojfnbdddfaoknhalnja";
            updateUrl = "https://clients2.google.com/service/update2/crx";
          }
        ];
      };
    })
  ];
}
