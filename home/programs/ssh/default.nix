{ config, pkgs, ... }:

{
  imports = [
    ./sshpass.nix
  ];
  programs.ssh = {
    enable = true;

    # Optional global defaults
    extraConfig = ''
      ServerAliveInterval 30
      ServerAliveCountMax 3
      VisualHostKey no
      HashKnownHosts yes
      IdentitiesOnly yes
      # ControlMaster auto
      # ControlPersist 5m
    '';

    # If you also keep small per-host snippets:
    # includes = [ "~/.ssh/config.d/*.conf" ];

    # Declarative Host blocks
    matchBlocks = {
      # Personal GitHub (uses ~/.ssh/id_ed25519)
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identitiesOnly = true;
        identityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
      };

      # Example: separate key/host alias for org remotes (optional)
      # Use `git@github-dacoso:ORG/REPO.git` as remote to trigger this block.
      "github-dacoso" = {
        hostname = "github.com";
        user = "git";
        identitiesOnly = true;
        identityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519_dacoso" ];
      };
    };
  };

  # (Optional) ensure the folder for extra snippets exists
  # home.file.".ssh/config.d/.keep".text = "";
}
