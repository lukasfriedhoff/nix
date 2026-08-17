# Custom library functions for this Nix monorepo.
# Import this in flake.nix or modules to use the helpers.

{ lib }:

{
  # Import all files matching a given name from a directory tree (recursive).
  #
  # Usage:
  #   imports = myLib.importTreeByName ./modules/features "nixos.nix";
  importTreeByName =
    dir: fileName:
    let
      recurse =
        current:
        let
          entries = builtins.readDir current;
          matchingFiles = lib.filterAttrs (name: type: type == "regular" && name == fileName) entries;
          dirs = lib.filterAttrs (_name: type: type == "directory") entries;
          filesHere = map (name: current + "/${name}") (builtins.attrNames matchingFiles);
          filesInDirs = lib.concatMap (name: recurse (current + "/${name}")) (builtins.attrNames dirs);
        in
        filesHere ++ filesInDirs;
    in
    recurse dir;

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

  # Resolve a secret path against the first root that contains it.
  # Falls back to the first root when no candidate exists on disk, so a
  # missing file still fails loudly at the sops/consumer layer instead of
  # silently disappearing from the build.
  #
  # Usage:
  #   myLib.resolveSecretFirst { roots = [ secrets.primary secrets.profileShared ]; path = "openai.env"; }
  resolveSecretFirst =
    {
      roots ? [ ],
      path,
    }:
    let
      nonNullRoots = builtins.filter (root: root != null) roots;
      candidates = map (root: "${root}/${path}") nonNullRoots;
      existing = builtins.filter builtins.pathExists candidates;
    in
    if path == null then
      null
    else if lib.hasPrefix "/" path then
      path
    else if existing != [ ] then
      builtins.head existing
    else if candidates != [ ] then
      builtins.head candidates
    else
      throw "resolveSecretFirst: relative path '${path}' requires at least one root";
}
