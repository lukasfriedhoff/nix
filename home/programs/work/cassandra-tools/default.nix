{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.programs."cassandra-tools";
in
{
  options.programs."cassandra-tools" = {
    enable = lib.mkEnableOption "Cassandra tooling bundle";
  };

  config = lib.mkMerge [
    {
      programs."cassandra-tools".enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      home.packages = [
        pkgs.cassandra
        (import ./dsbulk.nix { inherit pkgs lib; })
      ];
    })
  ];
}
