{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.programs.kubectl;
in
{
  options.programs.kubectl = {
    enable = lib.mkEnableOption "kubectl tooling bundle";
  };

  config = lib.mkMerge [
    {
      programs.kubectl.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
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
    })
  ];
  imports = [
    ./plugins.nix
  ];
}
