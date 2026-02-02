{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.moonlight;
in
{
  options.programs.moonlight = {
    enable = lib.mkEnableOption "Moonlight game streaming client";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.moonlight-qt;
      defaultText = lib.literalExpression "pkgs.moonlight-qt";
      description = "Moonlight package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.desktopEntries."moonlight" = lib.mkIf (!pkgs.stdenv.isDarwin) {
      name = "Moonlight";
      comment = "Stream games from your PC with NVIDIA GameStream or Sunshine";
      exec = "${cfg.package}/bin/moonlight";
      categories = [
        "Game"
        "Network"
      ];
      terminal = false;
    };
  };
}
