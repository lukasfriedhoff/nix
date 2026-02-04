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
      programs.cyberduck.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      home.packages = with pkgs; [
        cyberduck
      ];
    })
  ];
}
