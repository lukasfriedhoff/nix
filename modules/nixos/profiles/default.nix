{ lib, ... }:

let
  myLib = import ../../../lib { inherit lib; };
  excluded = [
    ./dacoso
    ./server
  ];
  subdirs = myLib.importSubdirs ./.;
in
{
  imports = lib.filter (path: !(lib.elem path excluded)) subdirs;
}
