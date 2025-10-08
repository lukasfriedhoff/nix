{ pkgs, ... }:
{
  home.packages = with pkgs; [
    sshpass
  ];
}