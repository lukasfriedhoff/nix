{ config, pkgs, lib, ... }:
{
  # Core kubectl & CLI tools
  home.packages = with pkgs; [
    kubectl
    kubectx
    stern
    # Add more as needed
  ];
}
