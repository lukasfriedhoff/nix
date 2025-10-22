{ config, pkgs, ... }:

{
  imports = [
    ./sshpass.nix
  ];

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    # Default host (applies to all)
    matchBlocks."*" = {
      user = "lukasfriedhoff";
      identitiesOnly = true;
    };

    extraConfig = ''
      ServerAliveInterval 30
      ServerAliveCountMax 3
      VisualHostKey no
      HashKnownHosts yes
      IdentitiesOnly yes
      # ControlMaster auto
      # ControlPersist 5m
    '';

    matchBlocks = {
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
    };
  };
}
