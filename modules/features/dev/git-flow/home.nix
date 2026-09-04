{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.git-flow;
in
{
  options.programs.git-flow = {
    enable = lib.mkEnableOption "git-flow support for lazygit";

    package = lib.mkPackageOption pkgs "git-flow" { };
  };

  config = lib.mkIf cfg.enable {
    programs.git-flow.package = pkgs.git-flow;

    # Add git-flow to lazygit configuration
    programs.lazygit.settings = {
      git = {
        # Enable git-flow integration in lazygit
        flow = {
          enable = true;
        };
      };
    };
  };
}
