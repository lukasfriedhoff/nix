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
  idleDimmer = pkgs.writeShellApplication {
    name = "gnome-idle-dimmer";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.upower
      pkgs.glib
    ];
    text = ''
      set -euo pipefail

      display_device="$(${pkgs.upower}/bin/upower -e | grep -m1 'DisplayDevice' || true)"
      if [ -z "$display_device" ]; then
        echo "gnome-idle-dimmer: could not find UPower DisplayDevice" >&2
        exit 1
      fi

      apply_timeout() {
        target="$1"
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.session idle-delay "$target"
      }

      last_state="__unset"
      while true; do
        state="$(${pkgs.upower}/bin/upower -i "$display_device" | ${pkgs.gawk}/bin/awk -F':' '/state/ {gsub(/ /, \"\", $2); print $2; exit}')"
        if [ -z "$state" ]; then
          sleep 30
          continue
        fi

        if [ "$state" != "$last_state" ]; then
          if [ "$state" = "discharging" ]; then
            apply_timeout 120
          else
            apply_timeout 300
          fi
          last_state="$state"
        fi

        sleep 30
      done
    '';
  };
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
    ./programs/chromium/default.nix
    ./programs/evolution/default.nix
    # Theme customisations applied via stylix' home module.
    ./programs/stylix/default.nix
    ./programs/codex/default.nix
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
    basePackages ++ lib.optionals (!isDarwin) linuxPackages ++ [
      pkgs.pavucontrol
      pkgs.jdownloader2
    ];

  home.sessionVariables = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    EDITOR = "vi";
    VISUAL = "vi";
    MOZ_ENABLE_WAYLAND = "1";
    MOZ_DRM_DEVICE = "/dev/dri/card1";
    DRI_PRIME = "0";
  };

  programs.evolution = {
    enable = true;
    nextcloud.enable = true;
  };

  systemd.user.services."gnome-idle-dimmer" = {
    Unit = {
      Description = "Adjust GNOME idle dim timeout based on power source";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${idleDimmer}/bin/gnome-idle-dimmer";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
