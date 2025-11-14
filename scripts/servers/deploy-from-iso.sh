#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  cat <<'USAGE'
Usage: scripts/servers/deploy-from-iso.sh <nixosConfiguration> <target> [extra nixos-anywhere args...]

Examples:
  scripts/servers/deploy-from-iso.sh docker-host-01 root@10.7.5.5
  scripts/servers/deploy-from-iso.sh smc-gpu-01 root@192.168.42.15 --kexec

This is a thin wrapper around nixos-anywhere. The first argument must match a nixosConfigurations.<name>
defined in the flake. The target is the SSH destination of the temporary installer environment.
USAGE
  exit 1
fi

config="$1"
target="$2"
shift 2

flake=".#${config}"

echo ">> Deploying ${flake} to ${target}"
export NIX_CONFIG="experimental-features = nix-command flakes"
nix run github:nix-community/nixos-anywhere -- \
  --target "${target}" \
  --flake "${flake}" \
  "$@"
