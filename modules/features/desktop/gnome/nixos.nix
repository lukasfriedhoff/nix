{
  config,
  lib,
  pkgs,
  linuxUser,
  ...
}:

let
  cfg = config.desktop.gnome;
  firefoxIntel = pkgs.firefox-bin.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postInstall = (old.postInstall or "") + ''
      wrapProgram $out/bin/firefox \
        --set MOZ_ENABLE_WAYLAND 1
    '';
  });
in
{
  options.desktop.gnome = {
    enable = lib.mkEnableOption "GNOME desktop profile";
  };

  config = lib.mkIf cfg.enable {
    services.xserver = {
      enable = true;
      xkb = {
        layout = "us,de";
        variant = ",nodeadkeys";
        options = "grp:alt_shift_toggle";
      };
    };

    services.displayManager.gdm = {
      enable = true;
      wayland = true;
    };

    services.desktopManager.gnome.enable = true;
    services.gnome.gnome-keyring.enable = true;
    services.gnome.gnome-online-accounts.enable = true;
    services.gnome.evolution-data-server.enable = true;
    services.printing.enable = true;

    programs.firefox = {
      enable = true;
      package = firefoxIntel;
    };
    environment.systemPackages = with pkgs; [
      vim
      wget
      gnomeExtensions.appindicator
      gnomeExtensions.kimpanel
    ];

    networking.networkmanager.enable = true;

    users.users.${linuxUser} = {
      isNormalUser = true;
      description = "Lukas Friedhoff";
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
      packages = with pkgs; [ gnome-terminal ];
      subUidRanges = [
        {
          startUid = 100000;
          count = 65536;
        }
      ];
      subGidRanges = [
        {
          startGid = 100000;
          count = 65536;
        }
      ];
    };

    environment.variables.EDITOR = lib.mkForce "vim";

    services.openssh.enable = true;
    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };

    programs.seahorse.enable = true;

    # Keep USB keyboards/mice from entering autosuspend.
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="usb", ENV{ID_USB_INTERFACES}=="*:030101:*", TEST=="power/control", ATTR{power/control}="on"
      ACTION=="add", SUBSYSTEM=="usb", ENV{ID_USB_INTERFACES}=="*:030102:*", TEST=="power/control", ATTR{power/control}="on"
    '';

    nixpkgs.config.allowUnfree = true;
  };
}
