{ lib, ... }:

{
  config = {
    shared.network.domain = lib.mkDefault "lab.h4xx.io";
  };
}
