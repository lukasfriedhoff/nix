{ lib, ... }:

let
  myLib = import ../../../../lib { inherit lib; };
  excluded = [
    ./gnome.nix
    ./plasma.nix
    ./laptop.nix
  ];
  autoImports = myLib.importTree ./.;
in
{
  imports = lib.filter (path: !(lib.elem path excluded)) autoImports;
}
