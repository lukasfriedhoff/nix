{ config, lib, pkgs, ... }:

{
  imports = [
    ./gitignore-io.nix
  ];
  home.activation.ensureGitDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/git/lukasfriedhoff" "$HOME/git/dacoso-devops"
  '';

  programs.git = {
    enable = true;
    lfs.enable = true;

    # Personal identity (hidden via GitHub noreply)
    userName  = "lukasfriedhoff";
    userEmail = "155996615+lukasfriedhoff@users.noreply.github.com";

    signing = {
      key = "7357275F6DFB9956E72B5BF9F52D0D35FC8BD0DF";
      signByDefault = true;
    };

    # Sensible defaults
    extraConfig = {
      init.defaultBranch = "main";
      pull.ff            = "only";
      push.default       = "current";
      core.autocrlf      = "input";
      user.useConfigOnly = true;
      gpg.format         = "openpgp";
      gpg.program        = "gpg";

      "includeIf \"gitdir:~/git/lukasfriedhoff/\"".path = "~/.gitconfig-personal";
      "includeIf \"gitdir:~/git/dacoso-devops/\"".path = "~/.gitconfig-dacoso-devops";
    };
  };

  # personal per-path config
  home.file.".gitconfig-personal".text = ''
    [user]
      name = lukasfriedhoff
      email = 155996615+lukasfriedhoff@users.noreply.github.com
      signingkey = 7357275F6DFB9956E72B5BF9F52D0D35FC8BD0DF
    [commit]
      gpgSign = true
    [gpg]
      program = gpg
  '';

  # org per-path config (fill in your org key fingerprint)
  home.file.".gitconfig-dacoso-devops".text = ''
    [user]
      name  = Lukas Friedhoff
      email = lukas.friedhoff@dacoso.com
      signingkey = 22C3C5DEAA39D79FB12328CFE43A3F179FCDD279
    [commit]
      gpgSign = true
    [gpg]
      program = gpg
  '';
}