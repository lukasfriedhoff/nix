#!/usr/bin/env bash
# Run formatting and flake checks for this repo.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if command -v rg >/dev/null 2>&1; then
  nix_files="$(rg --files -g '*.nix' -g '!examples/**' -g '!result/**')"
else
  nix_files="$(find . -name '*.nix' -not -path './examples/*' -not -path './result/*')"
fi

if [ -n "$nix_files" ]; then
  # Use nixfmt on explicit files to avoid generated directories.
  nix fmt -- --check $nix_files
else
  echo "No .nix files found for formatting check."
fi

nix flake check

# Optional: dry-run a subset of hosts, e.g.:
# NIX_CHECK_HOSTS="tux-h4xx-01 srv1" ./scripts/checks.sh
if [ -n "${NIX_CHECK_HOSTS:-}" ]; then
  for host in $NIX_CHECK_HOSTS; do
    nix build ".#nixosConfigurations.${host}.config.system.build.toplevel" --dry-run
  done
fi
