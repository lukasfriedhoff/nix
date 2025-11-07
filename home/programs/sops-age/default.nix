# nixos/home/programs/sops-age/default.nix
{ lib, pkgs, config, secrets, ... }:

let
  # The flake passes both profile-specific and shared roots.
  primaryDir = secrets.primary or secrets.root;
  sharedDir = secrets.shared or null;

  secretPath = name:
    let
      candidates =
        (lib.optional (primaryDir != null) "${primaryDir}/${name}")
        ++ (lib.optional (sharedDir != null) "${sharedDir}/${name}");
      found = lib.findFirst (p: builtins.pathExists p) null candidates;
    in
      if candidates == [ ] then
        throw "No secrets directory configured for ${name}"
      else
        if found != null then found else lib.head candidates;

  sopsBin = lib.getExe pkgs.sops;
  gpgBin = lib.getExe pkgs.gnupg;
  sshKeyPrivSecret = secretPath "git-personal-ed25519.priv";
  sshKeyPubSecret = secretPath "git-personal-ed25519.pub";
  gpgSecret = secretPath "git-personal-gpg.asc";
  openAIEnv = secretPath "openai.env";
  ageKeyFile = "${config.xdg.configHome}/sops/age/keys.txt";
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
        if [ -f '${gpgSecret}' ]; then
          ${sopsBin} -d '${gpgSecret}' | ${gpgBin} --batch --yes --import - || true
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

      export SOPS_AGE_KEY_FILE='${ageKeyFile}'

      cfg_dir="${config.xdg.configHome}/secrets"
      "${pkgs.coreutils}/bin/mkdir" -p "$cfg_dir"

      dst="$cfg_dir/openai.env"

      if [ -f '${openAIEnv}' ]; then
        tmp="$("${pkgs.coreutils}/bin/mktemp")"
        ${sopsBin} -d '${openAIEnv}' > "$tmp"
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
