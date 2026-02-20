# modules/features/devops/sops-age/home.nix
{
  lib,
  pkgs,
  config,
  secrets,
  workSystem ? false,
  ...
}:

let
  cfg = config.programs."sops-age";
in
{
  options.programs."sops-age" = {
    enable = lib.mkEnableOption "SOPS/age bootstrap";
  };

  config = lib.mkMerge [
    {
      programs."sops-age".enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable (
      let
        # The flake passes both profile-specific and shared roots.
        primaryDir = secrets.primary or secrets.root;
        profileSharedDir = secrets.profileShared or null;
        profileCommonDir = secrets.profileCommon or null;
        sharedDir = secrets.shared or null;

        secretPath =
          name:
          let
            candidates =
              (lib.optional (primaryDir != null) "${primaryDir}/${name}")
              ++ (lib.optional (profileSharedDir != null) "${profileSharedDir}/${name}")
              ++ (lib.optional (profileCommonDir != null) "${profileCommonDir}/${name}")
              ++ (lib.optional (sharedDir != null) "${sharedDir}/${name}");
            found = lib.findFirst (p: builtins.pathExists p) null candidates;
          in
          if candidates == [ ] then
            throw "No secrets directory configured for ${name}"
          else if found != null then
            found
          else
            lib.head candidates;

        sopsBin = lib.getExe pkgs.sops;
        gpgBin = lib.getExe pkgs.gnupg;
        sshKeyPrivSecret = secretPath "git-personal-ed25519.priv";
        gpgSecret = secretPath "git-personal-gpg.asc";
        openAIEnv = secretPath "openai.env";
        nextcloudConfig = secretPath "nextcloud/nextcloud.cfg.txt";
        nextcloudExclude = secretPath "nextcloud/sync-exclude.lst.txt";
        extraSshKeys = import ../../../../resources/ssh/keys.nix;
        extraSshConfigSnippets = import ../../../../resources/ssh/config-snippets.nix;
        managedSshFiles = (lib.optionals (!workSystem) extraSshKeys) ++ extraSshConfigSnippets;
        ageKeyFile = "${config.xdg.configHome}/sops/age/keys.txt";
        personalSshDir = "${config.home.homeDirectory}/.ssh/personal";
      in
      {
        home.packages = [
          pkgs.sops
          pkgs.age
        ];

        # still nice for interactive shells; activation exports explicitly too
        home.sessionVariables.SOPS_AGE_KEY_FILE = ageKeyFile;

        # --- existing: import personal GPG key if missing (unchanged) ---
        home.activation.importPersonalGitKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          set -eu
          export SOPS_AGE_KEY_FILE='${ageKeyFile}'

          if ! ${gpgBin} --list-secret-keys 7357275F6DFB9956E72B5BF9F52D0D35FC8BD0DF >/dev/null 2>&1; then
            if [ -f '${gpgSecret}' ]; then
              ${sopsBin} -d '${gpgSecret}' | ${gpgBin} --batch --yes --import - || true
            fi
          fi
        '';

        # --- robust SSH key install from SOPS, matching your filenames ---
        home.activation.installPersonalSshKey = lib.mkIf (!workSystem) (
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
            mkdir -p "${config.home.homeDirectory}/.ssh/config.d"
            chmod 700 "${config.home.homeDirectory}/.ssh/config.d"
            mkdir -p "${personalSshDir}"
            chmod 700 "${personalSshDir}"

            is_valid_ssh_key() {
              # `ssh-keygen -y` exits non-zero if the file isn't a valid private key.
              ${pkgs.openssh}/bin/ssh-keygen -y -f "$1" >/dev/null 2>&1
            }

            # If an old/broken key exists (empty or not PEM), remove it first
            if [ -f "${personalSshDir}/id_ed25519" ]; then
              if ! is_valid_ssh_key "${personalSshDir}/id_ed25519"; then
                echo "[HM][ssh] Removing malformed ${personalSshDir}/id_ed25519"
                rm -f "${personalSshDir}/id_ed25519"
              fi
            fi

            # Only install if we don't already have a good key
            if [ ! -f "${personalSshDir}/id_ed25519" ]; then
              if [ -f '${sshKeyPrivSecret}' ]; then
                tmpdir="$(mktemp -d)"
                trap 'rm -rf "$tmpdir"' EXIT

                # Decrypt to temp, then atomically move into place
                if ${sopsBin} -d '${sshKeyPrivSecret}' > "$tmpdir/priv"; then
                  if is_valid_ssh_key "$tmpdir/priv"; then
                    umask 177
                    mv -f "$tmpdir/priv" "${personalSshDir}/id_ed25519"
                    chmod 600 "${personalSshDir}/id_ed25519"
                    echo "[HM][ssh] Installed ${personalSshDir}/id_ed25519"
                  else
                    echo "[HM][ssh] Decrypted private key did not validate; aborting write"
                  fi
                else
                  echo "[HM][ssh] sops decryption failed for ${sshKeyPrivSecret}"
                fi

                ${pkgs.openssh}/bin/ssh-keygen -y -f "${personalSshDir}/id_ed25519" \
                  > "${personalSshDir}/id_ed25519.pub" || true
                chmod 644 "${personalSshDir}/id_ed25519.pub" || true
              else
                echo "[HM][ssh] Secret not found: ${sshKeyPrivSecret}"
              fi
            fi

            ln -sf "${personalSshDir}/id_ed25519" "${config.home.homeDirectory}/.ssh/id_ed25519"
            ln -sf "${personalSshDir}/id_ed25519.pub" "${config.home.homeDirectory}/.ssh/id_ed25519.pub"
          ''
        );

        home.activation.decryptOpenAIEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          set -eu

          export SOPS_AGE_KEY_FILE='${ageKeyFile}'

          cfg_dir="${config.xdg.configHome}/secrets"
          "${pkgs.coreutils}/bin/mkdir" -p "$cfg_dir"

          dst="$cfg_dir/openai.env"

          if [ -f '${openAIEnv}' ]; then
            tmp="$(mktemp)"
            ${sopsBin} -d '${openAIEnv}' > "$tmp"
            "${pkgs.coreutils}/bin/install" -m 600 "$tmp" "$dst"
            "${pkgs.coreutils}/bin/rm" -f "$tmp"
          elif [ -f "$dst" ]; then
            "${pkgs.coreutils}/bin/rm" -f "$dst"
          fi
        '';

        home.activation.installNextcloudConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          set -eu

          export SOPS_AGE_KEY_FILE='${ageKeyFile}'

          if [ ! -r "${ageKeyFile}" ]; then
            echo "[HM][nextcloud] Skipping: ${ageKeyFile} not found"
            exit 0
          fi

          cfg_dir="${config.xdg.configHome}/Nextcloud"
          "${pkgs.coreutils}/bin/mkdir" -p "$cfg_dir"

          install_secret() {
            secret="$1"
            dest="$2"

            if [ -f "$secret" ]; then
              tmp="$(mktemp)"
              if ${sopsBin} -d "$secret" > "$tmp"; then
                "${pkgs.coreutils}/bin/install" -m 600 "$tmp" "$dest"
                echo "[HM][nextcloud] Installed $(basename "$dest")"
              else
                echo "[HM][nextcloud] Failed to decrypt $secret"
              fi
              "${pkgs.coreutils}/bin/rm" -f "$tmp"
            fi
          }

          install_secret '${nextcloudConfig}' "$cfg_dir/nextcloud.cfg"
          install_secret '${nextcloudExclude}' "$cfg_dir/sync-exclude.lst"
        '';

        home.activation.installManagedSshKeys =
          let
            mkCommands =
              spec:
              let
                secretFile = secretPath spec.secret;
                mode = spec.mode or "600";
                dest = "${config.home.homeDirectory}/${spec.path}";
              in
              ''
                if [ -f '${secretFile}' ]; then
                  tmpfile="$(mktemp)"
                  if ${sopsBin} -d '${secretFile}' > "$tmpfile"; then
                    ${pkgs.coreutils}/bin/install -D -m ${mode} "$tmpfile" '${dest}'
                    echo "[HM][ssh] Installed ${spec.path}"
                  else
                    echo "[HM][ssh] Failed to decrypt ${secretFile}"
                  fi
                  ${pkgs.coreutils}/bin/rm -f "$tmpfile"
                else
                  echo "[HM][ssh] Secret not found: ${secretFile}"
                fi
              '';
          in
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              set -eu
              export SOPS_AGE_KEY_FILE='${ageKeyFile}'

            mkdir -p "${config.home.homeDirectory}/.ssh"
            chmod 700 "${config.home.homeDirectory}/.ssh"
            mkdir -p "${config.home.homeDirectory}/.ssh/config.d"
            chmod 700 "${config.home.homeDirectory}/.ssh/config.d"
            mkdir -p "${personalSshDir}"
            chmod 700 "${personalSshDir}"

              ${lib.concatMapStrings mkCommands managedSshFiles}
          '';

        # Ensure SSH uses that key for GitHub personal remotes
        programs.ssh.enable = lib.mkDefault true;
      }
    ))
  ];
}
