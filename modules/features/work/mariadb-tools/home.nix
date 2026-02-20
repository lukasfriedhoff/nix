{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.programs."mariadb-tools";
in
{
  options.programs."mariadb-tools" = {
    enable = lib.mkEnableOption "MariaDB client tools";
  };

  config = lib.mkMerge [
    {
      programs."mariadb-tools".enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      home.packages = [
        pkgs.mariadb.client
      ];
    })
  ];
}
