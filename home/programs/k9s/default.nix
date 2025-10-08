{ config, pkgs, ... }:

{
  programs.k9s = {
    enable = true;
    package = pkgs.k9s;
  };
}