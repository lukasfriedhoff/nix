{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf config.programs.kubectl.enable {
    home.packages = with pkgs; [
      kubectl-tree
      kubectl-neat
    ];
  };
}
