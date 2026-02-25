{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.shadowTech;

  defaultPackage = pkgs.callPackage ../../../pkgs/shadow-client-appimage { };
  selectedPackage = cfg.package or defaultPackage;
  sandboxSource = "${selectedPackage}/opt/shadow-appimage/chrome-sandbox";
in
{
  options.lukasf.shadowTech = {
    enable = lib.mkEnableOption "Shadow PC client";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "pkgs.callPackage ../../../pkgs/shadow-client-appimage { }";
      description = "Shadow PC client package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ selectedPackage ];

    security.chromiumSuidSandbox.enable = lib.mkDefault true;

    security.wrappers.shadow-chrome-sandbox = {
      source = sandboxSource;
      owner = "root";
      group = "root";
      setuid = true;
    };
  };
}
