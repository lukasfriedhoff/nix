{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./sshpass.nix
  ];

  programs.ssh =
    let
      sshData = import ../../../resources/ssh/hosts.nix;

      identityFor =
        host:
        if lib.hasAttr "identityFile" host then
          host.identityFile
        else if host.identity or "" == "work" then
          sshData.defaults.workIdentity
        else
          sshData.defaults.personalIdentity;

      mkHostMatchBlock =
        host:
        {
          hostname = host.hostName or host.alias;
          user = host.user or sshData.defaults.user;
          port = host.port or sshData.defaults.port;
          identitiesOnly = true;
          identityFile = [ (identityFor host) ];
          controlMaster = "auto";
          controlPersist = host.controlPersist or sshData.defaults.controlPersist;
        }
        // (host.extraOptions or { });

      managedHostBlocks = lib.listToAttrs (
        map (host: {
          name = host.match or host.alias;
          value = mkHostMatchBlock host;
        }) sshData.hosts
      );
    in
    {
      enable = true;
      enableDefaultConfig = false;

      extraConfig = ''
        ServerAliveInterval 30
        ServerAliveCountMax 3
        VisualHostKey no
        HashKnownHosts yes
        IdentitiesOnly yes
      '';

      matchBlocks = {
        "*" = {
          user = "lukasfriedhoff";
          identitiesOnly = true;
        };
        "github.com" = {
          hostname = "github.com";
          user = "git";
          identitiesOnly = true;
          identityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
        };

        "github-dacoso" = {
          hostname = "github.com";
          user = "git";
          identitiesOnly = true;
          identityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519_dacoso" ];
        };

        "bitbucket.org" = {
          hostname = "bitbucket.org";
          user = "git";
          identitiesOnly = true;
          identityFile = [ "${config.home.homeDirectory}/.ssh/bitbucket" ];
        };
      }
      // managedHostBlocks;
    };
}
