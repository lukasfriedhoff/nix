{ lib, ... }:

let
  myLib = import ../../../../lib { inherit lib; };
in
{
  imports = myLib.importTree ./.;
}
