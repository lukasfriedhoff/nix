{
  pkgs,
  lib,
  macUser,
  linuxUser,
  ...
}:
let
  fallbackUser = if pkgs.stdenv.isDarwin then macUser else linuxUser;
  fallbackHome = if pkgs.stdenv.isDarwin then "/Users/${macUser}" else "/home/${linuxUser}";
in
{
  home = {
    username = lib.mkDefault fallbackUser;
    homeDirectory = lib.mkDefault fallbackHome;
    stateVersion = "25.05";
    file."hushlogin".text = "";
  };

  nixpkgs.config.allowUnfree = lib.mkDefault true;

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

}
