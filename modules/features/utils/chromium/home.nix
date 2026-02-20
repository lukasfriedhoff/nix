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
        extensions = [
          {
            # uBlock Origin
            id = "cjpalhdlnbpafiamejdnhcphjbkeiagm";
            updateUrl = "https://clients2.google.com/service/update2/crx";
          }
        ];
      };
    })
  ];
}
