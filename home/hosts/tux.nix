{ pkgs, lib, ... }:

{
  home.packages = lib.mkAfter [
    pkgs.podman
    pkgs.btop
  ];
}
