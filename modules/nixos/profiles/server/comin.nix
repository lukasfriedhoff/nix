{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.serverDeployment;
  # Public Git remote used by comin-managed machines.
  repoUrl = "https://github.com/lukasfriedhoff/nix";
in
{
  options.lukasf.serverDeployment = {
    enable = lib.mkEnableOption "server deployment defaults via comin" // {
      default = true;
    };

    enableComin = lib.mkEnableOption "comin-based deployment for ${repoUrl}" // {
      default = true;
    };
  };

  config = lib.mkIf (cfg.enable && cfg.enableComin) {
    services.comin = {
      enable = true;
      hostname = lib.mkDefault config.networking.hostName;
      repositorySubdir = ".";
      remotes = [
        {
          name = "origin";
          url = repoUrl;
          branches.main.name = "develop";
          branches.testing.name = "testing-${config.services.comin.hostname}";
        }
      ];
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/comin 0755 root root -"
    ];
  };
}
