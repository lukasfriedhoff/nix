{ config, pkgs, lib, ... }:
{
  home.packages = with pkgs; [
    kubectl-tree
    kubectl-neat
  ];
}