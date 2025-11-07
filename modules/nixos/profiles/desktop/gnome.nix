{ config, lib, pkgs, ... }:

{
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
  services.printing.enable = true;

  programs.firefox.enable = true;
  environment.systemPackages = with pkgs; [
    vim
    wget
    gnomeExtensions.appindicator
    gnomeExtensions.kimpanel
  ];

  # PipeWire stack (GNOME-on-Wayland default)
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  networking.networkmanager.enable = true;

  users.users.lukasf = {
    isNormalUser = true;
    description = "Lukas Friedhoff";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [ gnome-terminal ];
  };

  environment.variables.EDITOR = lib.mkForce "vim";

  services.openssh.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  nixpkgs.config.allowUnfree = true;
}
