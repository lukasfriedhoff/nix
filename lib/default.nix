# Custom library functions for this Nix monorepo.
# Import this in flake.nix or modules to use the helpers.

{ lib }:

{
  # Import all .nix files from a directory (non-recursive).
  # Returns a list of module paths suitable for use in `imports = [ ... ]`.
  #
  # Usage:
  #   imports = myLib.importDir ./programs;
  #
  # This imports all *.nix files directly in ./programs (not subdirectories).
  importDir =
    dir:
    let
      entries = builtins.readDir dir;
      nixFiles = lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) entries;
    in
    map (name: dir + "/${name}") (builtins.attrNames nixFiles);

  # Import all subdirectories that contain a default.nix.
  # Returns a list of directory paths suitable for use in `imports = [ ... ]`.
  #
  # Usage:
  #   imports = myLib.importSubdirs ./programs;
  #
  # This imports ./programs/foo, ./programs/bar, etc. if they have default.nix.
  importSubdirs =
    dir:
    let
      entries = builtins.readDir dir;
      dirs = lib.filterAttrs (name: type: type == "directory") entries;
      hasDefault = name: builtins.pathExists (dir + "/${name}/default.nix");
      validDirs = lib.filterAttrs (name: _: hasDefault name) dirs;
    in
    map (name: dir + "/${name}") (builtins.attrNames validDirs);

  # Import all modules from a directory tree (recursive).
  # Imports both direct .nix files and subdirectories with default.nix.
  #
  # Usage:
  #   imports = myLib.importTree ./modules;
  importTree =
    dir:
    let
      entries = builtins.readDir dir;

      # Direct .nix files (excluding default.nix to avoid double-import)
      nixFiles = lib.filterAttrs (
        name: type: type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix"
      ) entries;

      # Subdirectories with default.nix
      dirs = lib.filterAttrs (name: type: type == "directory") entries;
      hasDefault = name: builtins.pathExists (dir + "/${name}/default.nix");
      validDirs = lib.filterAttrs (name: _: hasDefault name) dirs;
    in
    (map (name: dir + "/${name}") (builtins.attrNames nixFiles))
    ++ (map (name: dir + "/${name}") (builtins.attrNames validDirs));

  # Resolve a secret path against a base directory.
  # If path is absolute, return it. If root is null, throw.
  #
  # Usage:
  #   myLib.resolveSecretPath { root = secrets.primary; path = "wireguard/key.txt"; }
  resolveSecretPath =
    {
      root ? null,
      path,
    }:
    if path == null then
      null
    else if lib.hasPrefix "/" path then
      path
    else if root != null then
      "${root}/${path}"
    else
      throw "resolveSecretPath: relative path '${path}' requires a root";
}
