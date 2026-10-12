#!/usr/bin/env bash
# Grant a work system read access to the second-brain vault, without ever
# putting a personal credential on it.
#
# Why a separate account: Forgejo access tokens are USER-WIDE - a token for
# lukasf can reach every repo lukasf can reach. SSH deploy keys would be
# per-repo but port 22 is not exposed through the Cloudflare tunnel, so an
# off-LAN machine cannot use them. A machine account added as a collaborator
# on this one repo is the only combination that is both per-repo and
# reachable over HTTPS.
#
# Run this once from a PERSONAL machine (needs the admin token). The vault
# token is written straight into nix-secrets, encrypted to the work age keys.
set -euo pipefail

FORGEJO="${FORGEJO:-https://git.h4xx.io}"
MACHINE_USER="${MACHINE_USER:-workmac}"
REPO="${REPO:-lukasf/second-brain}"
PERMISSION="${PERMISSION:-read}" # read | write
SECRETS_REPO="${SECRETS_REPO:-$HOME/git/lukasfriedhoff/nix-secrets}"
OUT="$SECRETS_REPO/secrets/profiles/work/shared/forgejo/second-brain-token.yaml"

admin_token() {
  sops -d "$SECRETS_REPO/secrets/profiles/personal/shared/forgejo/admin-token.yaml" 2>/dev/null \
    | yq eval '.forgejo.admin_token' - 2>/dev/null
}

TOKEN="${FORGEJO_ADMIN_TOKEN:-$(admin_token)}"
if [ -z "${TOKEN:-}" ] || [ "$TOKEN" = "null" ]; then
  echo "Need an admin token with write:admin scope." >&2
  echo "Create one at $FORGEJO/user/settings/applications (scopes: write:admin, write:user)" >&2
  echo "then re-run with:  FORGEJO_ADMIN_TOKEN=... $0" >&2
  exit 1
fi

api() { curl -sS --max-time 30 -H "Authorization: token $TOKEN" -H "Content-Type: application/json" "$@"; }

# 1. Machine account (idempotent)
if api "$FORGEJO/api/v1/users/$MACHINE_USER" | grep -q '"login"'; then
  echo "user $MACHINE_USER exists"
else
  echo "creating user $MACHINE_USER"
  pw="$(head -c 32 /dev/urandom | base64 | tr -d '/+=')"
  api -X POST "$FORGEJO/api/v1/admin/users" -d "$(printf '{"username":"%s","email":"%s@h4xx.io","password":"%s","must_change_password":false,"send_notify":false,"full_name":"Work MacBook (machine account)"}' \
    "$MACHINE_USER" "$MACHINE_USER" "$pw")" >/dev/null
  unset pw
fi

# 2. Collaborator on the vault ONLY
echo "granting $PERMISSION on $REPO"
api -X PUT "$FORGEJO/api/v1/repos/$REPO/collaborators/$MACHINE_USER" \
  -d "$(printf '{"permission":"%s"}' "$PERMISSION")" >/dev/null

# 3. Token for the machine account. Forgejo requires BASIC auth to mint a
#    token, so this uses sudo on behalf of the machine account instead.
echo "creating access token"
resp="$(api -X POST "$FORGEJO/api/v1/users/$MACHINE_USER/tokens?sudo=$MACHINE_USER" \
  -d '{"name":"second-brain-workmac","scopes":["read:repository"]}')"
sha="$(printf '%s' "$resp" | yq eval '.sha1' - 2>/dev/null)"
if [ -z "$sha" ] || [ "$sha" = "null" ]; then
  echo "token creation failed: $resp" >&2
  echo "Fallback: log in as $MACHINE_USER in the web UI and create a token" >&2
  echo "with scope read:repository, then pipe it in:" >&2
  echo "  printf '%s' '<token>' | $0 --store-stdin" >&2
  exit 1
fi

# 4. Encrypt into nix-secrets (work rules already cover this path, so it is
#    readable by the two work Mac age keys and by nobody else).
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
printf 'forgejo:\n    second_brain_token: %s\n' "$sha" > "$tmp"
sops --encrypt --input-type yaml --output-type yaml "$tmp" > "$OUT"
echo "wrote $OUT"
echo
echo "Next: commit nix-secrets, then on the work Mac:"
echo "  darwin-rebuild switch --flake ~/git/lukasfriedhoff/nix#work-mbp-01"
echo "  git clone $FORGEJO/$REPO ~/git/lukasfriedhoff/second-brain"
