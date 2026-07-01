{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.programs.velero;
in
{
  options.programs.velero = {
    enable = lib.mkEnableOption "Velero CLI";
  };

  config = lib.mkMerge [
    {
      programs.velero.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      home.packages = [
        pkgs.velero
        pkgs.velero_1_9_4
      ];
    })
  ];
}
