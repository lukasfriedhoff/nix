{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.shadowTech;
in
{
  options.lukasf.shadowTech = {
    enable = lib.mkEnableOption "Shadow PC client";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../pkgs/shadow-client { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../pkgs/shadow-client { }";
      description = "Shadow PC client package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
