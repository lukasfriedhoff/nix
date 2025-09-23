{ pkgs, lib, ... }:

{
  # Use nix-daemon (multi-user) and enable flakes
  services.nix-daemon.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Hostname (macOS will present this on the network as MacBook-Pro.local)
  networking.hostName = "MacBook-Pro";

  # Shell & basics
  programs.zsh.enable = true;
  environment.systemPackages = with pkgs; [
    git vim wget jq
  ];

  environment.systemPackages = [ pkgs.age pkgs.sops ];

  # Nice-to-have: TouchID for sudo on supported Macs
  security.pam.enableSudoTouchIdAuth = true;

  # Some sensible macOS defaults (tweak as you like)
  system.defaults = {
    dock.autohide = true;
    finder.AppleShowAllExtensions = true;
    NSGlobalDomain.AppleShowAllExtensions = true;
  };

  # Fonts example
  fonts.packages = with pkgs; [ inter jetbrains-mono noto-fonts-emoji ];

  # Required by nix-darwin; don’t bump casually
  system.stateVersion = 5;
}
