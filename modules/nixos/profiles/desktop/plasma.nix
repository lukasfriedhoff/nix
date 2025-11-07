{ config, lib, pkgs, ... }:

{
  # Desktop environment (Plasma 6)
  services = {
    xserver = {
      enable = true;
      xkb = {
        layout = "us,de";
        variant = ",nodeadkeys";
        options = "grp:alt_shift_toggle";
      };
    };
    displayManager.sddm.enable = true;
    desktopManager.plasma6.enable = true;
    printing.enable = true;
  };

  # Audio (PipeWire stack)
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Desktop user setup
  users.users.lukasf = {
    isNormalUser = true;
    description = "Lukas Friedhoff";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [ kdePackages.kate ];
  };

  networking.networkmanager.enable = true;

  programs.firefox.enable = true;
  environment.systemPackages = with pkgs; [
    vim
    wget
  ];

  environment.variables.EDITOR = lib.mkForce "vim";

  # SSH server and GPG agent integration
  services.openssh.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Desktops are allowed to use unfree software (e.g. vscode, proprietary drivers).
  nixpkgs.config.allowUnfree = true;
}
