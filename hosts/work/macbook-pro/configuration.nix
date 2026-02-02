{
  pkgs,
  macUser,
  ...
}:
{
  networking.hostName = "macbook-pro";

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
