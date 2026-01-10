{ pkgs, ... }:

{
  home.packages = [
    pkgs.mariadb.client
  ];
}
