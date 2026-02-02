{
  pkgs,
  lib,
  ...
}:
{
  programs.chromium = lib.mkIf (!pkgs.stdenv.isDarwin) {
    enable = true;
    package = pkgs.chromium;
    extensions = [
      {
        # uBlock Origin
        id = "cjpalhdlnbpafiamejdnhcphjbkeiagm";
        updateUrl = "https://clients2.google.com/service/update2/crx";
      }
    ];
  };
}
