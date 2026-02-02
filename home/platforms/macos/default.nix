{
  pkgs,
  lib,
  config,
  ...
}:
{
  # macOS-specific Home Manager configuration.
  # This module is imported on all platforms but only activates on Darwin.

  home.packages = lib.mkIf pkgs.stdenv.isDarwin (
    with pkgs;
    [
      # macOS CLI utilities
      coreutils # GNU coreutils (gls, gcat, etc.)
      gnugrep # GNU grep
      gawk # GNU awk
      findutils # GNU find/xargs
      watch # watch command

      # Development tools
      iproute2mac # ip command for macOS (renamed from darwin.iproute2mac)

      # System utilities
      pstree # process tree viewer
      terminal-notifier # macOS notifications from CLI
    ]
  );

  # macOS-specific session variables
  home.sessionVariables = lib.mkIf pkgs.stdenv.isDarwin {
    # Use GNU coreutils by default (prefixed with 'g')
    # Users can alias specific commands if needed
    HOMEBREW_NO_ANALYTICS = "1";
  };

  # macOS-specific shell aliases
  programs.bash.shellAliases = lib.mkIf pkgs.stdenv.isDarwin {
    # Clipboard integration
    pbcopy = "pbcopy";
    pbpaste = "pbpaste";

    # Quick Look from terminal
    ql = "qlmanage -p";

    # Open Finder in current directory
    finder = "open -a Finder .";

    # Flush DNS cache
    flushdns = "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder";

    # Show/hide hidden files in Finder
    showhidden = "defaults write com.apple.finder AppleShowAllFiles YES; killall Finder";
    hidehidden = "defaults write com.apple.finder AppleShowAllFiles NO; killall Finder";
  };

  # AeroSpace tiling window manager
  programs.aerospace.enable = lib.mkIf pkgs.stdenv.isDarwin (lib.mkDefault true);

  # SketchyBar status bar
  programs.sketchybar.enable = lib.mkIf pkgs.stdenv.isDarwin (lib.mkForce false);

  # XDG directories on macOS
  xdg = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    # macOS-appropriate XDG paths
    cacheHome = "${config.home.homeDirectory}/Library/Caches";
    configHome = "${config.home.homeDirectory}/.config";
    dataHome = "${config.home.homeDirectory}/.local/share";
    stateHome = "${config.home.homeDirectory}/.local/state";
  };
}
