#!/usr/bin/env bash
# Run one of the bundled scripts with openpyxl + Pillow available (NixOS has no
# global python packages).  Usage: run.sh add_evening.py SPEC.json --out OUT.xlsx
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$1"; shift
args=()
for a in "$@"; do args+=("$(printf '%q' "$a")"); done
exec nix-shell -p "python3.withPackages (ps: [ps.openpyxl ps.pillow])" \
  --run "python3 $(printf '%q' "$dir/$script") ${args[*]:-}"
