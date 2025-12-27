#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/servers/deploy-from-iso.sh <nixosConfiguration> <target> [--luks-secret <sops-file>] [extra nixos-anywhere args...]

Examples:
  scripts/servers/deploy-from-iso.sh docker-host-01 root@10.7.5.5
  scripts/servers/deploy-from-iso.sh my-homelab-node root@192.168.42.15 --kexec
  scripts/servers/deploy-from-iso.sh srv1 root@10.1.30.12 --luks-secret secrets/profiles/personal/shared/luks/srv1.txt

This is a thin wrapper around nixos-anywhere. The first argument must match a nixosConfigurations.<name>
defined in the flake. The target is the SSH destination of the temporary installer environment.
USAGE
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

config="$1"; target="$2"; shift 2
luks_secret=""
extra_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --luks-secret)
      luks_secret="$2"
      shift 2
      ;;
    -h|--help)
      usage; exit 0
      ;;
    *)
      extra_args+=("$1")
      shift
      ;;
  esac
done

flake=".#${config}"

tmp_key=""
cleanup() { [[ -n "$tmp_key" && -f "$tmp_key" ]] && rm -f "$tmp_key"; }
trap cleanup EXIT

if [[ -n "$luks_secret" ]]; then
  if ! command -v sops >/dev/null 2>&1; then
    echo "error: sops not found but --luks-secret was provided" >&2
    exit 2
  fi
  tmp_key="$(mktemp)"
  SOPS_CONFIG="${SOPS_CONFIG:-${PWD}/.sops.yaml}" sops -d "$luks_secret" > "$tmp_key"
  extra_args+=(--disk-encryption-keys /tmp/luks.key "$tmp_key")
fi

copy_host_keys=true
for arg in "${extra_args[@]}"; do
  if [[ "$arg" == "--copy-host-keys" ]]; then
    copy_host_keys=false
    break
  fi
done
if [[ "$copy_host_keys" == true ]]; then
  extra_args+=(--copy-host-keys)
fi

echo ">> Deploying ${flake} to ${target}"
# Make sure initrd SSH host key exists on the installer so boot.initrd.network.ssh.hostKeys can read it.
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${target}" \
  "mkdir -p /etc/ssh && if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then ssh-keygen -t ed25519 -N '' -f /etc/ssh/ssh_host_ed25519_key; fi" || {
  echo "error: failed to create initrd SSH host key on target ${target}" >&2
  exit 3
}

export NIX_CONFIG="experimental-features = nix-command flakes"
nix run github:nix-community/nixos-anywhere -- \
  --flake "${flake}" \
  "${target}" \
  "${extra_args[@]}"
