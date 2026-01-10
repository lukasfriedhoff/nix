{ pkgs, lib, ... }:

{
  home.packages = [
    pkgs.cassandra
    (import ./dsbulk.nix { inherit pkgs lib; })
  ];
}
