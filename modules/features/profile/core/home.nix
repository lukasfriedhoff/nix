# Core profile options for Home Manager
# Defines profile enable flags that other modules check
{
  lib,
  profile ? null,
  ...
}:

let
  personalDesktopProfiles = [
    "srv4"
    "tux"
    "tab"
    "lenovo"
  ];
in
{
  options.profiles = {
    desktop = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = profile != null && lib.elem profile personalDesktopProfiles;
        description = "Enable desktop home profile with GUI applications and development tools.";
      };
    };
  };

  # Core configuration shared by all profiles
  config = {
    # Ensure home-manager doesn't conflict with system nix
    nix.package = lib.mkDefault null;
  };
}
