{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:

let
  cfg = config.services.comin;
  # Public Git remote used by comin-managed machines.
  repoUrl = "https://github.com/lukasfriedhoff/nix";
in
{
  options.lukasf.serverDeployment = {
    enableComin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Toggle for the opinionated comin setup that keeps servers in sync
        with the <literal>${repoUrl}</literal> flake.
      '';
    };
  };

  config = lib.mkIf config.lukasf.serverDeployment.enableComin {
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
