{
  config,
  lib,
  pkgs,
  ...
}:

# Caffeine: macOS menu bar app that keeps the Mac awake (nixpkgs build of
# IntelliScape/caffeine). Started at login via LaunchServices - GUI agents
# launched with open behave like regular apps (see easy-move-resize).
let
  cfg = config.programs.caffeine;
in
{
  options.programs.caffeine = {
    enable = lib.mkEnableOption "Caffeine keep-awake menu bar app";

    package = lib.mkPackageOption pkgs "caffeine" { };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isDarwin;
        message = "programs.caffeine is a macOS menu bar app.";
      }
    ];

    home.packages = [ cfg.package ];

    launchd.agents.caffeine = {
      enable = true;
      config = {
        ProgramArguments = [
          "/usr/bin/open"
          "-W"
          "${cfg.package}/Applications/Caffeine.app"
        ];
        KeepAlive = true;
        RunAtLoad = true;
        ProcessType = "Interactive";
      };
    };
  };
}
