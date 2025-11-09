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
  fallbackUser = if isDarwin then macUser else linuxUser;
  fallbackHome =
    if isDarwin then
      "/Users/${macUser}"
    else
      "/home/${linuxUser}";
in
{
  home = {
    username = lib.mkDefault fallbackUser;
    homeDirectory = lib.mkDefault fallbackHome;
    stateVersion = "25.05";
    file."hushlogin".text = "";
  };

  nixpkgs.config.allowUnfree = lib.mkDefault true;

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
    ./programs/cassandra-tools/default.nix
    ./programs/mariadb-tools/default.nix
    ./programs/vscode/default.nix
    # Theme customisations applied via stylix' home module.
    ./programs/stylix/default.nix
    #./programs/codex/default.nix
  ];

  home.packages =
    let
      basePackages = with pkgs; [
        zip
        xz
        unzip
        p7zip
        jq
        yq
        fzf
        tmux
        ripgrep
        dnsutils
        file
        which
        tree
        gnupg
        gnused
        gnutar
        nixfmt-rfc-style
        btop
        lsof
      ];

      linuxPackages = with pkgs; [
        iftop
        pciutils
        usbutils
      ];
    in
    basePackages ++ lib.optionals (!isDarwin) linuxPackages;

  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    EDITOR = "vi";
    VISUAL = "vi";
  };

}
