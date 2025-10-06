{ config, lib, pkgs, ... }:

let
  # Pick your templates here (lowercase, dash-separated; see gitignore.io for names)
  templates = [
    "macos" "linux" "vim" "direnv" "node" "go" "python"
  ];

  giUrl = "https://www.toptal.com/developers/gitignore/api/${lib.concatStringsSep "," templates}";
in {
  # Make sure curl exists for activation-time fetch
  home.packages = [ pkgs.curl ];

  # Ensure Git reads the global ignore file from XDG
  programs.git = {
    enable = true;
    extraConfig.core.excludesFile = "${config.xdg.configHome}/git/ignore";
  };

  # Generate ~/.config/git/ignore on each switch (impure: network)
  home.activation.gitignoreIO = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -e
    mkdir -p "${config.xdg.configHome}/git"
    echo "Updating global gitignore from gitignore.io..."
    ${pkgs.curl}/bin/curl -fsSL "${giUrl}" > "${config.xdg.configHome}/git/ignore"
  '';
}