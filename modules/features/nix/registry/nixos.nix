{
  config,
  lib,
  pkgs,
  inputs ? { },
  ...
}:

let
  cfg = config.lukasf.nixRegistry;

  inputRegistries = {
    nixpkgs = inputs.nixpkgs or null;
  }
  // lib.optionalAttrs (inputs ? nixpkgs-unstable-small) {
    unstable = inputs.nixpkgs-unstable-small;
  }
  // lib.optionalAttrs (inputs ? nixpkgs-legacy-2511) {
    legacy = inputs.nixpkgs-legacy-2511;
  };

  baseRegistry = lib.mapAttrs (_: flake: { inherit flake; }) (
    lib.filterAttrs (_: v: v != null) inputRegistries
  );

  nixPath =
    lib.optionals cfg.includeNixpkgsPath [ "nixpkgs=${pkgs.path}" ]
    ++ lib.optionals (cfg.includeInputPaths && inputs ? nixpkgs-unstable-small) [
      "unstable=${inputs.nixpkgs-unstable-small}"
    ]
    ++ lib.optionals (cfg.includeInputPaths && inputs ? nixpkgs-legacy-2511) [
      "legacy=${inputs.nixpkgs-legacy-2511}"
    ]
    ++ cfg.extraNixPath;
in
{
  options.lukasf.nixRegistry = {
    enable = lib.mkEnableOption "Nix registry and nixPath defaults" // {
      default = true;
    };

    includeNixpkgsPath = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add nixpkgs to nix.nixPath.";
    };

    includeInputPaths = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add registry-backed inputs to nix.nixPath when available.";
    };

    extraRegistry = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional nix.registry entries to merge with the defaults.";
    };

    extraNixPath = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional entries appended to nix.nixPath.";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.registry = lib.mkMerge [
      (lib.mkDefault baseRegistry)
      cfg.extraRegistry
    ];

    nix.nixPath = lib.mkDefault nixPath;
  };
}
