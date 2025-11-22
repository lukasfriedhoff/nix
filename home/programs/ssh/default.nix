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

  # Fix key directory permissions on activation so ssh-agent and ssh honor keys
  home.activation.fixSshPerms = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    chmod 700 "${config.home.homeDirectory}/.ssh"
    find "${config.home.homeDirectory}/.ssh" -type d -exec chmod 700 {} +
    find "${config.home.homeDirectory}/.ssh" -type f -exec chmod 600 {} +
  '';

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
        SetEnv TERM=xterm
        ServerAliveInterval 30
        ServerAliveCountMax 3
        VisualHostKey no
        HashKnownHosts yes
        IdentitiesOnly yes
        Include ~/.ssh/config.d/chaospott
      '';

      matchBlocks = {
        "*" = {
          identitiesOnly = true;
        };
        "*.chaospott.de" = {
          user = "h4xx";
          identitiesOnly = true;
          identityFile = [ "${config.home.homeDirectory}/.ssh/personal/chaospott/noc" ];
        };
        "git.chaospott.de" = {
          user = "git";
          identitiesOnly = true;
          identityFile = [ "${config.home.homeDirectory}/.ssh/personal/chaospott/git" ];
        };
        "10.42.1.28" = {
          identitiesOnly = true;
          identityFile = [ "${config.home.homeDirectory}/.ssh/personal/chaospott/door" ];
        };
        "10.42.1.20" = {
          identitiesOnly = true;
          identityFile = [ "${config.home.homeDirectory}/.ssh/personal/chaospott/door" ];
        };
        "github.com" = {
          hostname = "github.com";
          user = "git";
          identitiesOnly = true;
          identityFile = [ "${config.home.homeDirectory}/.ssh/personal/id_ed25519" ];
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
