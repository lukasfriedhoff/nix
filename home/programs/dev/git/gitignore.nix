{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Prefetched from gitignore.io; refresh with ./scripts/update-gitignore.sh when templates change.
  globalGitignore = ../../../../resources/gitignore/global.gitignore;
in
{
  config = lib.mkIf config.programs.git.enable {
    # For a fully reproducible fetch, replace the local file with a fetchurl + nix hash.
    xdg.configFile."git/ignore".source = globalGitignore;
  };
}
