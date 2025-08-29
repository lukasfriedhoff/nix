{ lib, pkgs, config, ... }:

let
  repo = "${config.home.homeDirectory}/git/lukasfriedhoff/nix";
  sopsBin = "${pkgs.sops}/bin/sops";
  gpgBin  = "${pkgs.gnupg}/bin/gpg";
in
{
  home.packages = [ pkgs.sops pkgs.age ];

  # Nice for interactive shells, but HM activation won't rely on this
  home.sessionVariables.SOPS_AGE_KEY_FILE =
    "${config.home.homeDirectory}/.config/sops/age/keys.txt";

  # Auto-import personal GPG signing key at switch/login if missing
  home.activation.importPersonalGitKey =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -eu

      # Ensure SOPS sees the age private key in the activation environment
      export SOPS_AGE_KEY_FILE="${config.home.homeDirectory}/.config/sops/age/keys.txt"

      # Only import if the key isn't already present
      if ! ${gpgBin} --list-secret-keys 7357275F6DFB9956E72B5BF9F52D0D35FC8BD0DF >/dev/null 2>&1; then
        if [ -f "${repo}/secrets/git-personal-gpg.asc" ]; then
          # No passphrase on this key now; import non-interactively
          ${sopsBin} -d "${repo}/secrets/git-personal-gpg.asc" \
            | ${gpgBin} --batch --yes --import -
        fi
      fi
    '';
}
