# shellcheck shell=bash
# Shared helpers for scripts in this repo. Source it, do not execute it:
#
#   . "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
#
# (adjust the number of ".." segments to the sourcing script's depth).

# Guard against double-sourcing.
if [[ -n "${LUKASF_COMMON_SH_SOURCED:-}" ]]; then
  return 0
fi
LUKASF_COMMON_SH_SOURCED=1

log() {
  printf '>> %s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

# Emit the default non-interactive SSH -o options, one per line.
# Usage (bash 3.2 safe):
#   while IFS= read -r opt; do ssh_cmd+=(-o "$opt"); done < <(ssh_base_opts)
ssh_base_opts() {
  printf '%s\n' \
    "StrictHostKeyChecking=no" \
    "UserKnownHostsFile=/dev/null" \
    "ConnectTimeout=5" \
    "ConnectionAttempts=1"
}

# Root of the nix config repo this library lives in.
_common_repo_root() {
  (cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
}

# Resolve the private nix-secrets checkout and print its path.
# Default location is a sibling checkout of this repo (../nix-secrets);
# override with NIX_SECRETS_DIR. Dies loudly when the checkout is missing.
secrets_root() {
  local root
  root="${NIX_SECRETS_DIR:-$(_common_repo_root)/../nix-secrets}"
  if [[ ! -d "$root" ]]; then
    die "nix-secrets checkout not found at ${root}
Clone github.com/lukasfriedhoff/nix-secrets there, or point NIX_SECRETS_DIR at your checkout."
  fi
  if [[ ! -f "${root}/.sops.yaml" ]]; then
    die "${root} exists but has no .sops.yaml; it does not look like a nix-secrets checkout.
Point NIX_SECRETS_DIR at a valid nix-secrets checkout."
  fi
  (cd "$root" && pwd)
}

# Print the sops config path inside the nix-secrets checkout.
sops_config() {
  local root
  root="$(secrets_root)" || exit 1
  printf '%s\n' "${root}/.sops.yaml"
}
