{ config, pkgs, ... }:

{
  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # LUKS (keep your UUID)
  boot.initrd.luks.devices."luks-84295891-6d10-4a08-a2fc-442738205455".device =
    "/dev/disk/by-uuid/84295891-6d10-4a08-a2fc-442738205455";

  # Networking
  networking.networkmanager.enable = true;

  # Time & locale
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  # GUI (Plasma 6)
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Printing
  services.printing.enable = true;

  # Audio (PipeWire)
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # User
  users.users.lukasf = {
    isNormalUser = true;
    description = "Lukas Friedhoff";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [ kdePackages.kate ];
    # Set password using initialPassword or hashedPassword if you want it managed here:
    # initialPassword = "changeme";
    # hashedPassword = "...";
  };

  # Apps & system packages
  programs.firefox.enable = true;
  environment.systemPackages = with pkgs; [
    vim wget
  ];

  # Editor env
  environment.variables.EDITOR = "vim";

  # GnuPG agent (system-level) + SSH support
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # SSH server
  services.openssh.enable = true;

  # Unfree allowed
  nixpkgs.config.allowUnfree = true;

  # Enable flakes/new nix command
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # State version
  system.stateVersion = "25.05";
}
