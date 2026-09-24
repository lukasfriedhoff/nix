#!/usr/bin/env bash
# Rebuild a personal host that is too far behind to bootstrap itself.
#
# The problem this solves: attic and the remote builder are configured *by* the
# flake, so a host whose running generation predates them has neither in its
# /etc/nix/nix.conf. Left alone it compiles the whole closure locally against
# cache.nixos.org - painful on a tablet. This passes both on the command line
# for the one rebuild that installs them permanently.
#
# Run this ON the host being rebuilt.

set -euo pipefail

ATTIC_URL="https://attic.h4xx.io/homelab?priority=30"
ATTIC_KEY="homelab:KFrqDSi76JxQ7V7R6j5PGM+T9Nk/2A/+CLmp5/G76Hg="
BUILDER_HOST="srv8.lab.h4xx.io"
BUILDER_PORT="30610"
BUILDER_KEY="/var/lib/sops-nix/ssh/srv3-builder-key"
BUILDER_HOSTKEY_B64="c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSURVQXEydnpZRk1SREhPMlVWa2EyZkNWWG9Pd3JNV2F1eTZKamxWZUlibDUgbml4LXJlbW90ZS1idWlsZGVyLXByb2Q="
FLAKE_REF_DEFAULT="github:lukasfriedhoff/nix/develop"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: scripts/personal/rebuild-with-cache.sh [options] [<host>]

Rebuilds <host> (default: this machine's hostname) from the flake, forcing use
of the attic cache and the in-cluster remote builder even when the running
generation does not yet know about them.

Options:
  --flake <ref>     Flake ref (default: github:lukasfriedhoff/nix/develop)
  --install-keys    Install this host's declared authorized_keys first, so the
                    machine becomes reachable over ssh BEFORE the rebuild.
  --local-fallback  Allow building locally if the remote builder is unreachable.
                    Off by default: on a slow machine you want a loud failure,
                    not six silent hours of compiling.
  --action <a>      switch (default), boot, test, dry-activate
  -n, --dry-run     Show what would be fetched/built, change nothing.
  -h, --help        This text.

Must run as root (nix restricts substituters/builders to trusted-users, which
is root only here - as a normal user the daemon DISCARDS them and you compile
locally with only a warning). Use `sudo`, never `nixos-rebuild --sudo`: the
latter evaluates as your user and hits exactly that trap.

The flake pulls a private input (nix-secrets) over ssh and desktops do not
provision a key for root, so forward your agent:

  sudo --preserve-env=SSH_AUTH_SOCK scripts/personal/rebuild-with-cache.sh ...
EOF
}

HOST=""
FLAKE_REF="$FLAKE_REF_DEFAULT"
INSTALL_KEYS=0
LOCAL_FALLBACK=0
ACTION="switch"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --flake)
      FLAKE_REF="${2:?--flake needs a value}"
      shift 2
      ;;
    --install-keys)
      INSTALL_KEYS=1
      shift
      ;;
    --local-fallback)
      LOCAL_FALLBACK=1
      shift
      ;;
    --action)
      ACTION="${2:?--action needs a value}"
      shift 2
      ;;
    -n | --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) die "unknown option: $1 (try --help)" ;;
    *)
      HOST="$1"
      shift
      ;;
  esac
done

[[ -n "$HOST" ]] || HOST="$(hostname)"
[[ "$(id -u)" -eq 0 ]] || die "must run as root (see --help)"

# --- authorized_keys bootstrap ------------------------------------------------
# Pulled from the flake rather than pasted by hand, so there is one source of
# truth. The nix repo is public, so this works before the host can reach
# anything private.
if [[ "$INSTALL_KEYS" -eq 1 ]]; then
  log "extracting authorized keys for $HOST from $FLAKE_REF"
  keys="$(
    nix eval --raw --no-write-lock-file \
      "${FLAKE_REF}#nixosConfigurations.${HOST}.config.users.users.lukasf.openssh.authorizedKeys.keys" \
      --apply 'ks: builtins.concatStringsSep "\n" ks' 2>/dev/null || true
  )"
  [[ -n "$keys" ]] || die "no authorized keys declared for $HOST - add them to its configuration.nix first"

  install_keys_for() {
    local home="$1" owner="$2"
    install -d -m 700 -o "$owner" -g "$(id -gn "$owner")" "$home/.ssh"
    local f="$home/.ssh/authorized_keys"
    touch "$f"
    while IFS= read -r k; do
      [[ -n "$k" ]] || continue
      grep -qxF "$k" "$f" || printf '%s\n' "$k" >>"$f"
    done <<<"$keys"
    chmod 600 "$f"
    chown "$owner:$(id -gn "$owner")" "$f"
    log "authorized_keys updated for $owner ($(grep -c . "$f") entries)"
  }
  install_keys_for /root root
  [[ -d /home/lukasf ]] && install_keys_for /home/lukasf lukasf
fi

# --- preflight ----------------------------------------------------------------
log "preflight"

nix_ver="$(nix --version | awk '{print $3}')"
printf '    nix %s\n' "$nix_ver"

curl -fsS -o /dev/null --max-time 15 "https://attic.h4xx.io/homelab/nix-cache-info" \
  || die "attic unreachable - without it this rebuild is a full local compile"
printf '    attic reachable\n'

# The flake pulls a PRIVATE input over ssh:
#   nix-secrets.url = git+ssh://git@github.com/lukasfriedhoff/nix-secrets
# and lukasf.nixSecretsAccess is false on desktops, so root here has no key of
# its own. Evaluation therefore depends on a forwarded agent. Check it now:
# failing at this line is far kinder than a cryptic fetch error twenty minutes
# into a rebuild.
if ! nix eval --raw --no-write-lock-file \
  "${FLAKE_REF}#nixosConfigurations.${HOST}.config.system.stateVersion" >/dev/null 2>&1; then
  cat >&2 <<EOF
error: cannot evaluate ${FLAKE_REF}#${HOST}

  Most likely the private nix-secrets input is unreachable as root. It is
  fetched over ssh from git@github.com, and this host does not provision a
  key of its own (lukasf.nixSecretsAccess = false).

  Re-run preserving your agent, and make sure the key is loaded:

    ssh-add -l                       # as your normal user; must list a key
    ssh -T git@github.com            # seeds known_hosts, expect a greeting
    sudo --preserve-env=SSH_AUTH_SOCK $0 $*

EOF
  exit 1
fi
printf '    flake evaluates (private input reachable)\n'

use_builder=0
if [[ ! -r "$BUILDER_KEY" ]]; then
  warn "builder key $BUILDER_KEY absent (this generation predates it) - attic only"
elif ! ssh -i "$BUILDER_KEY" -p "$BUILDER_PORT" \
  -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
  "root@${BUILDER_HOST}" true 2>/dev/null; then
  # srv8 is LAN/VPN-only while attic is public, so this genuinely differs.
  warn "builder ${BUILDER_HOST}:${BUILDER_PORT} unreachable (on the LAN/VPN?) - attic only"
else
  use_builder=1
  printf '    remote builder reachable\n'
fi

opts=(
  --option extra-substituters "$ATTIC_URL"
  --option extra-trusted-public-keys "$ATTIC_KEY"
  --option builders-use-substitutes true
)

if [[ "$use_builder" -eq 1 ]]; then
  # Full URI with an explicit port: the `nix-builder-prod` ssh_config alias only
  # exists in the NEW generation, which is precisely what we do not have yet.
  opts+=(
    --option builders
    "ssh://root@${BUILDER_HOST}:${BUILDER_PORT} x86_64-linux ${BUILDER_KEY} 2 2 kvm,big-parallel - ${BUILDER_HOSTKEY_B64}"
  )
  if [[ "$LOCAL_FALLBACK" -eq 0 ]]; then
    # Without this nix still tries locally first and only then the hook, so a
    # builder that dies mid-run silently becomes hours of local compilation.
    opts+=(--option max-jobs 0)
  fi
elif [[ "$LOCAL_FALLBACK" -eq 0 ]]; then
  die "no remote builder and --local-fallback not given; refusing to compile locally"
fi

target="${FLAKE_REF}#${HOST}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log "dry run: what would be fetched vs built"
  exec nix build --dry-run "${opts[@]}" \
    "${FLAKE_REF}#nixosConfigurations.${HOST}.config.system.build.toplevel"
fi

log "nixos-rebuild $ACTION --flake $target"
printf '    builder: %s\n' "$([[ $use_builder -eq 1 ]] && echo "${BUILDER_HOST}:${BUILDER_PORT}" || echo 'none (attic only)')"
exec nixos-rebuild "$ACTION" --flake "$target" "${opts[@]}"
