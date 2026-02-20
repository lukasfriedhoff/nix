{ lib, ... }:

let
  myLib = import ../../../lib { inherit lib; };
  subdirs = myLib.importSubdirs ./.;
in
{
  imports = subdirs;
}
