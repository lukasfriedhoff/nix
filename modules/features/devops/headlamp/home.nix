{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.programs.headlamp;
in
{
  options.programs.headlamp = {
    enable = lib.mkEnableOption "Headlamp Kubernetes desktop UI";
    package = lib.mkPackageOption pkgs "headlamp" { };
  };

  # Desktop-only: this is an Electron app, so it is not enabled by default the
  # way the CLI bundles are. Servers have no use for it.
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # Headlamp reads the same kubeconfig as everything else. It is spelled out
    # here rather than relied upon because Headlamp resolves KUBECONFIG at
    # launch from the desktop entry's environment, not from a login shell.
    home.sessionVariables.KUBECONFIG = lib.mkDefault config.programs.kubeconfig.configPath;
  };
}
