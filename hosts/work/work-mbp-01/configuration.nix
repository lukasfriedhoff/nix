_: {
  networking.hostName = "work-mbp-01";

  # Let root fetch the private nix-secrets flake input during
  # `sudo darwin-rebuild switch` (deploy key installed out of band).
  lukasf.nixSecretsAccess.enable = true;

  home-manager.users.lukasfriedhoff = {
    programs.dockerHeadless.enable = true;
  };

  # host-specific homebrew casks
  homebrew.casks = [
    "aerospace"
  ];

  # SketchyBar via homebrew tap
  homebrew.taps = [
    "FelixKratz/formulae"
  ];
  homebrew.brews = [
    "sketchybar"
  ];
}
