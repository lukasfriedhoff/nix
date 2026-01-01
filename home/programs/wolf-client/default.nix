{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.wolfClient;
in
{
  options.programs.wolfClient = {
    enable = lib.mkEnableOption "Moonlight client tooling for Wolf hosts";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.moonlight-qt;
      description = "Moonlight client package to install.";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional client-side packages to install alongside Moonlight.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      cfg.package
    ]
    ++ cfg.extraPackages;
  };
}
