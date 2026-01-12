#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/homelab/unlock.sh <host> [<secret-path> [<remote-path>]]

Decrypts the LUKS passphrase (SOPS-encrypted) and streams it to the initrd
SSH listener for the given host, writing the passphrase to the target path
(default: /crypt-ramfs/passphrase) with mode 600 so the boot process can continue.

Defaults:
  secret-path: secrets/profiles/personal/shared/luks/<host>.txt
  ssh target:  unlock-<host> (defined in resources/ssh/hosts/personal.nix)
  remote-path: /crypt-ramfs/passphrase
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 3 ]]; then
  usage >&2
  exit 1
fi

host="$1"
secret="${2:-secrets/profiles/personal/shared/luks/${host}.txt}"
target="unlock-${host}"
remote_path="${3:-/crypt-ramfs/passphrase}"

if [[ ! -f "$secret" ]]; then
  echo "error: secret not found: $secret" >&2
  exit 1
fi

SOPS_CONFIG="${SOPS_CONFIG:-${PWD}/.sops.yaml}"
echo ">> Unlocking ${host} via ${target} using ${secret} -> ${remote_path}"

# Stream the decrypted passphrase directly into the remote path with secure perms.
sops -d "$secret" | ssh "$target" "umask 077; install -m 600 /dev/stdin '${remote_path}'"

echo ">> Passphrase delivered to ${target}:${remote_path}"
