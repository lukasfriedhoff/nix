{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.programs.cyberduck;
in
{
  options.programs.cyberduck = {
    enable = lib.mkEnableOption "Cyberduck S3 client";
  };

  config = lib.mkMerge [
    {
      programs.cyberduck.enable = lib.mkDefault pkgs.stdenv.isDarwin;
    }
    (lib.mkIf (cfg.enable && pkgs.stdenv.isDarwin) {
      home.packages = with pkgs; [
        cyberduck
      ];
    })
  ];
}
