{
  config,
  lib,
  pkgs,
  ...
}:

# Sudoless CPU/GPU/ANE monitoring for Apple Silicon. Uses the local
# pkgs/macmon package (0.8.x) until nixpkgs moves past 0.6.1, which
# panics on the M5 Max (vladkens/macmon#47).
let
  cfg = config.programs.macmon;
in
{
  options.programs.macmon = {
    enable = lib.mkEnableOption "macmon Apple Silicon performance monitor";

    package = lib.mkPackageOption pkgs "macmon" { };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isDarwin;
        message = "programs.macmon is only available on macOS (Apple Silicon).";
      }
    ];

    home.packages = [ cfg.package ];
  };
}
