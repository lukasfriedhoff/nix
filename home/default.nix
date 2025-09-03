{ config, pkgs, ... }:

{
  home.username = "lukasf";
  home.homeDirectory = "/home/lukasf";

  # imports
  imports = [
    ./shell/bash/default.nix
    ./programs/alacritty/default.nix
    ./programs/starship/default.nix
    ./programs/git/default.nix
    ./programs/gpg/default.nix
    ./programs/sops-age/default.nix
  ];

  home.packages = with pkgs; [
    # archives
    zip
    xz
    unzip
    p7zip
    
    # utils
    jq
    yq
    fzf

    # network tools
    dnsutils # dig and nslookup
    
    # misc
    file
    which
    tree
    gnupg
    gnused
    gnutar

    # top tools
    btop
    iotop
    iftop

    # system tools
    sysstat
    lm_sensors
    ethtool
    pciutils
    usbutils
   
    # process monitoring stuff
    strace
    ltrace
    lsof
  ];

  home.stateVersion = "25.05";
}
