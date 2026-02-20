#!/usr/bin/env bash
# Refresh the prefetched gitignore bundle used by modules/features/dev/git/gitignore.nix.
set -euo pipefail

TEMPLATES=(macos linux vim direnv node go python)
TEMPLATE_STRING=$(IFS=,; echo "${TEMPLATES[*]}")
TARGET="$(git rev-parse --show-toplevel)/resources/gitignore/global.gitignore"

curl -fsSL "https://www.toptal.com/developers/gitignore/api/${TEMPLATE_STRING}" > "$TARGET"

echo "Refreshed gitignore. Current hash:"
nix hash path "$TARGET"
