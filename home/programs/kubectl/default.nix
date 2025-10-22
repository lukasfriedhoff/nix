{ config, pkgs, lib, ... }:
{
  # Core kubectl & CLI tools
  home.packages = with pkgs; [
    kubectl
    kubectx
    stern
    fluxcd
    kustomize
    kubernetes-helm
    # Add more as needed
  ];
  imports = [ 
    ./plugins.nix 
    ];
}
