{ self, ... }:
{
  # Enable Touch ID for sudo
  security.pam.services.sudo_local.touchIdAuth = true;

  system = {
    stateVersion = 25.05;
    configurationRevision = self.rev or self.dirtyRev or null;

    startup.chime = false;

    defaults = {
      loginwindow = {
        GuestEnabled = false;
        DisableConsoleAccess = true;
      };

      finder = {
        AppleShowAllFiles = true; # hidden files
        AppleShowAllExtensions = true; # file extensions
        _FXShowPosixPathInTitle = true; # title bar full path
        ShowPathbar = true; # breadcrumb nav at bottom
        ShowStatusBar = true; # file count & disk space
      };

      NSGlobalDomain = {
        NSAutomaticSpellingCorrectionEnabled = false;
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticWindowAnimationsEnabled = false;
      };
    };

    # Extra activation logic for locale defaults
    activationScripts.setLocale.text = ''
      echo "Setting macOS locale and language defaults..."
      defaults write -g AppleLocale -string "en_US"
      defaults write -g AppleLanguages -array "en-US"
      defaults write -g AppleMeasurementUnits -string "Centimeters"
      defaults write -g AppleTemperatureUnit -string "Celsius"
    '';
  };

  environment.variables = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
  };
}
