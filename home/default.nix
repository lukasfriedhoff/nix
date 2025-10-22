{ 
  config, 
  pkgs, 
  lib,
  macUser, 
  linuxUser,  
  ... 
}:
let
  isDarwin = pkgs.stdenv.isDarwin;
  user     = if isDarwin then macUser else linuxUser;
  homeDir  = if isDarwin then "/Users/${macUser}" else "/home/${linuxUser}";
in
{
  home = {
    username      = lib.mkDefault user;
    homeDirectory = lib.mkDefault homeDir;
    stateVersion = "25.05";
    file."hushlogin".text = "";
  };

  # imports
  imports = [
    ./shell/bash/default.nix
    ./programs/alacritty/default.nix
    ./programs/starship/default.nix
    ./programs/git/default.nix
    ./programs/lazygit/default.nix
    ./programs/neovim/default.nix
    ./programs/gpg/default.nix
    ./programs/ssh/default.nix
    ./programs/sops-age/default.nix
    ./programs/k9s/default.nix
    ./programs/kubectl/default.nix
    ./programs/velero/default.nix
    ./programs/s3/default.nix
    ./programs/maven-config/default.nix
    #./programs/stylix/default.nix      # theming
    ./programs/cassandra-tools/default.nix
    ./programs/mariadb-tools/default.nix
    ./programs/vscode/default.nix
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
    tmux
    ripgrep

    # network tools
    dnsutils # dig and nslookup
    
    # misc
    file
    which
    tree
    gnupg
    gnused
    gnutar
    nixfmt-rfc-style

    # top tools
    btop
    #iotop
    iftop

    # system tools
    #sysstat
    #lm_sensors
    #ethtool
    pciutils
    usbutils
    
    # process monitoring stuff
    #strace
    #ltrace
    lsof
  ];
  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    EDITOR = "vi";
    VISUAL = "vi";
  };

}
