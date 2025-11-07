{ lib, ... }:

{
  # Locale & time shared across every machine (desktop & server).
  time.timeZone = "Europe/Berlin";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
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
  };

  # Core Nix settings shared by all systems. Per-profile modules decide on allowUnfree.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Default state version
  system.stateVersion = lib.mkDefault "25.05";
}
