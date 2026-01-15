{
  config,
  pkgs,
  lib,
  macUser,
  linuxUser,
  profile ? null,
  ...
}:
let
  fallbackUser = if pkgs.stdenv.isDarwin then macUser else linuxUser;
  fallbackHome = if pkgs.stdenv.isDarwin then "/Users/${macUser}" else "/home/${linuxUser}";
  personalDesktopProfiles = [
    "srv4"
    "tux"
    "tab"
  ];
  installEvolutionOnProfile =
    (!pkgs.stdenv.isDarwin) && profile != null && lib.elem profile personalDesktopProfiles;
in
{
  home = {
    username = lib.mkDefault fallbackUser;
    homeDirectory = lib.mkDefault fallbackHome;
    stateVersion = "25.05";
    file."hushlogin".text = "";
  };

  nixpkgs.config.allowUnfree = lib.mkDefault true;

  imports = [
    # Shell configuration
    ./shell/bash/default.nix

    # Program categories (organized by purpose)
    ./programs/dev # Development: git, neovim, vscode, lazygit, codex, claude
    ./programs/devops # DevOps: kubectl, k9s, velero, s3, sops-age
    ./programs/utils # Utilities: alacritty, starship, gpg, ssh
    ./programs/work # Work tools: cassandra-tools, mariadb-tools, maven-config
    ./programs/gaming # Gaming: icarus, icarus-mod-manager

    # Standalone programs
    ./programs/evolution/default.nix
    ./programs/chromium/default.nix

    # Theme customizations applied via stylix home module
    ./programs/stylix/default.nix

    # Platform-specific configuration
    ./platforms/linux/default.nix
    ./platforms/macos/default.nix
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
        nixfmt
        nixfmt-tree
        btop
        lsof
      ];

      linuxPackages = with pkgs; [
        iftop
        pciutils
        usbutils
        wl-clipboard
        intel-gpu-tools
        iotop
        (linuxPackages_latest.turbostat or linuxPackages.turbostat)
      ];
      desktopPackages = with pkgs; [
        python3
      ];
    in
    basePackages ++ lib.optionals (!pkgs.stdenv.isDarwin) linuxPackages ++ desktopPackages;

  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    EDITOR = "vi";
    VISUAL = "vi";
  };

  programs.evolution = lib.mkIf installEvolutionOnProfile {
    enable = true;
    nextcloud.enable = true;
  };
}
