{
  config,
  lib,
  repoRoot ? null,
  ...
}:

let
  cfg = config.lukasf.facter;
  hostName = config.networking.hostName or null;
  hostRoots =
    if repoRoot == null || hostName == null then
      [ ]
    else
      [
        (repoRoot + "/hosts/personal/${hostName}")
        (repoRoot + "/hosts/homelab/${hostName}")
        (repoRoot + "/hosts/work/${hostName}")
      ];
  hostRoot = lib.findFirst (path: builtins.pathExists path) null hostRoots;
  facterReport = if hostRoot == null then null else hostRoot + "/facter.json";
  hasReport = facterReport != null && builtins.pathExists facterReport;
in
{
  options.lukasf.facter = {
    enable = lib.mkEnableOption "nixos-facter report integration";
    reportPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a nixos-facter report (facter.json).";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf hasReport {
      lukasf.facter.enable = lib.mkDefault true;
      lukasf.facter.reportPath = lib.mkDefault facterReport;
    })
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.reportPath != null;
          message = "lukasf.facter.reportPath must be set when enabled.";
        }
        {
          assertion = cfg.reportPath != null && builtins.pathExists cfg.reportPath;
          message = "lukasf.facter.reportPath does not exist: ${toString cfg.reportPath}";
        }
      ];
      hardware.facter.reportPath = cfg.reportPath;
    })
  ];
}
