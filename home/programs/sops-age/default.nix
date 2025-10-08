# nixos/home/programs/sops-age/default.nix
{ lib, pkgs, config, ... }:

let
  repo    = "${config.home.homeDirectory}/git/lukasfriedhoff/nix";
  sopsBin = "${pkgs.sops}/bin/sops";
  gpgBin  = "${pkgs.gnupg}/bin/gpg";
  sshKeyPrivSecret = "${repo}/secrets/personal/git-personal-ed25519.priv";
  sshKeyPubSecret  = "${repo}/secrets/personal/git-personal-ed25519.pub";
  ageKeyFile       = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
in
{
  home.packages = [ pkgs.sops pkgs.age ];

  # still nice for interactive shells; activation exports explicitly too
  home.sessionVariables.SOPS_AGE_KEY_FILE = ageKeyFile;

  # --- existing: import personal GPG key if missing (unchanged) ---
  home.activation.importPersonalGitKey =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -eu
      export SOPS_AGE_KEY_FILE='${ageKeyFile}'

      if ! ${gpgBin} --list-secret-keys 7357275F6DFB9956E72B5BF9F52D0D35FC8BD0DF >/dev/null 2>&1; then
        if [ -f '${repo}/secrets/personal/git-personal-gpg.asc' ]; then
          ${sopsBin} -d '${repo}/secrets/personal/git-personal-gpg.asc' | ${gpgBin} --batch --yes --import - || true
        fi
      fi
    '';

  # --- robust SSH key install from SOPS, matching your filenames ---
  home.activation.installPersonalSshKey =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -eu
      export SOPS_AGE_KEY_FILE='${ageKeyFile}'

      # If the age key file isn't present, skip gracefully
      if [ ! -r "${ageKeyFile}" ]; then
        echo "[HM][ssh] Skipping: ${ageKeyFile} not found"
        exit 0
      fi

      mkdir -p "${config.home.homeDirectory}/.ssh"
      chmod 700 "${config.home.homeDirectory}/.ssh"

      # If an old/broken key exists (empty or not PEM), remove it first
      if [ -f "${config.home.homeDirectory}/.ssh/id_ed25519" ]; then
        if ! head -n1 "${config.home.homeDirectory}/.ssh/id_ed25519" | grep -q '^-----BEGIN OPENSSH PRIVATE KEY-----'; then
          echo "[HM][ssh] Removing malformed ~/.ssh/id_ed25519"
          rm -f "${config.home.homeDirectory}/.ssh/id_ed25519"
        fi
      fi

      # Only install if we don't already have a good key
      if [ ! -f "${config.home.homeDirectory}/.ssh/id_ed25519" ]; then
        if [ -f '${sshKeyPrivSecret}' ]; then
          tmpdir="$(mktemp -d)"
          trap 'rm -rf "$tmpdir"' EXIT

          # Decrypt to temp, then atomically move into place
          if ${sopsBin} -d '${sshKeyPrivSecret}' > "$tmpdir/priv"; then
            if head -n1 "$tmpdir/priv" | grep -q '^-----BEGIN OPENSSH PRIVATE KEY-----'; then
              umask 177
              mv -f "$tmpdir/priv" "${config.home.homeDirectory}/.ssh/id_ed25519"
              chmod 600 "${config.home.homeDirectory}/.ssh/id_ed25519"
              echo "[HM][ssh] Installed ~/.ssh/id_ed25519"
            else
              echo "[HM][ssh] Decrypted private key did not look like an OpenSSH key; aborting write"
            fi
          else
            echo "[HM][ssh] sops decryption failed for ${sshKeyPrivSecret}"
          fi

          # Public key: decrypt if encrypted, else copy if plain, else derive
          if [ -f '${sshKeyPubSecret}' ]; then
            if ${sopsBin} -d --output /dev/null '${sshKeyPubSecret}' >/dev/null 2>&1; then
              ${sopsBin} -d '${sshKeyPubSecret}' > "${config.home.homeDirectory}/.ssh/id_ed25519.pub" || true
            else
              cp -f '${sshKeyPubSecret}' "${config.home.homeDirectory}/.ssh/id_ed25519.pub" || true
            fi
            chmod 644 "${config.home.homeDirectory}/.ssh/id_ed25519.pub" || true
          else
            ${pkgs.openssh}/bin/ssh-keygen -y -f "${config.home.homeDirectory}/.ssh/id_ed25519" \
              > "${config.home.homeDirectory}/.ssh/id_ed25519.pub" || true
            chmod 644 "${config.home.homeDirectory}/.ssh/id_ed25519.pub" || true
          fi
        else
          echo "[HM][ssh] Secret not found: ${sshKeyPrivSecret}"
        fi
      fi
    '';

  home.activation.decryptOpenAIEnv =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -eu

    export SOPS_AGE_KEY_FILE="${config.home.homeDirectory}/.config/sops/age/keys.txt"

    # ensure secrets dir exists
    "${pkgs.coreutils}/bin/mkdir" -p "${config.home.homeDirectory}/.config/secrets"

    src="${config.home.homeDirectory}/git/lukasfriedhoff/nix/secrets/personal/openai.env"
    dst="${config.home.homeDirectory}/.config/secrets/openai.env"

    if [ -f "$src" ]; then
      tmp="$("${pkgs.coreutils}/bin/mktemp")"
      "${pkgs.sops}/bin/sops" -d "$src" > "$tmp"
      "${pkgs.coreutils}/bin/install" -m 600 "$tmp" "$dst"
      "${pkgs.coreutils}/bin/rm" -f "$tmp"
    fi
  '';

  # Ensure SSH uses that key for GitHub personal remotes
  programs.ssh = {
    enable = true;
    matchBlocks."github.com" = {
      hostname = "github.com";
      user = "git";
      identitiesOnly = true;
      identityFile = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];
    };
  };
}
