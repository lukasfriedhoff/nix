# Core profile options for Home Manager
# Defines profile enable flags that other modules check
{
  lib,
  profile ? null,
  ...
}:

let
  # Single source of truth for which profiles are personal desktops.
  # Other home modules must consume config.profiles.desktop.enable instead
  # of duplicating this list.
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

      nixLd = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Point LD_LIBRARY_PATH at the NixOS nix-ld loader directory
            (/run/current-system/sw/share/nix-ld/lib). All current desktop
            profiles run on NixOS (including standalone Home Manager on
            those hosts), so this defaults to true; disable it for a
            desktop profile on a non-NixOS system.
          '';
        };
      };
    };
  };

  # Core configuration shared by all profiles
  config = {
    # Ensure home-manager doesn't conflict with system nix
    nix.package = lib.mkDefault null;
  };
}
