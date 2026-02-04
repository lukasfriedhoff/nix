#!/usr/bin/env bash
# Query a live installer for homelab bootstrap details.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/homelab/probe-installer.sh --target root@IP [--host <name>] [--write-hw <path>]

Queries a running NixOS installer (or live system) for details needed to fill the homelab template:
  - hardware-configuration.nix from nixos-generate-config
  - disk inventory (lsblk + /dev/disk/by-id)
  - network interfaces

Nothing is written unless --write-hw is provided; results are printed to stdout.

Examples:
  scripts/homelab/probe-installer.sh --target root@10.1.30.12 --host srv1 \
    --write-hw hosts/homelab/srv1/hardware-configuration.nix

EOF
}

die() { echo "error: $*" >&2; exit 1; }

target=""
host=""
write_hw=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) target="$2"; shift 2;;
    --host) host="$2"; shift 2;;
    --write-hw) write_hw="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown arg: $1";;
  esac
done

[[ -n "$target" ]] || die "--target root@IP is required"

ssh_opts=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ControlMaster=auto
  -o ControlPath="/tmp/nh-probe-%r@%h:%p"
  -o ControlPersist=60
)

cmd=$(
  cat <<'EOF'
set -euo pipefail
echo "## hardware-configuration.nix"
nixos-generate-config --show-hardware-config
echo
echo "## disks (lsblk)"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
echo
echo "## disk by-id (excluding loop)"
ls -l /dev/disk/by-id | grep -v loop || true
echo
echo "## network interfaces"
ip -o link show | awk '{print $2, $9}' | sed 's/://'
EOF
)

echo "==> probing ${target}"
out="$(ssh "${ssh_opts[@]}" "${target}" "$cmd")"

hw_cfg_sanitized="$(
  python3 -c 'import sys
text = sys.stdin.read().splitlines()
hardware = []
collect = False
for line in text:
    if line.startswith("## hardware-configuration.nix"):
        collect = True
        continue
    if collect and line.startswith("## disks"):
        break
    if collect:
        hardware.append(line)

# Sanitize: drop fileSystems.* and swapDevices blocks (disko will define FS)
out = []
skip = False
for line in hardware:
    if line.lstrip().startswith("fileSystems.") or line.lstrip().startswith("swapDevices"):
        skip = True
    if not skip:
        out.append(line)
    if skip and line.strip() == "":
        skip = False

sanitized = "\n".join(out).strip()
if not sanitized:
    # Fallback to raw hardware config if sanitisation accidentally removed everything.
    sanitized = "\n".join(hardware).strip()
print(sanitized + ("\n" if sanitized else ""))' <<< "$out"
)"

printf "%s\n" "$out"

if [[ -n "$write_hw" ]]; then
  if [[ -z "$hw_cfg_sanitized" ]]; then
    echo "error: sanitized hardware config is empty, refusing to write ${write_hw}" >&2
    exit 1
  fi
  echo ">> writing sanitized ${write_hw} (fileSystems/swapDevices removed; use disko)"
  mkdir -p "$(dirname "$write_hw")"
  printf "%s" "$hw_cfg_sanitized" > "$write_hw"
fi

if [[ -n "$host" ]]; then
  echo
  echo "==> suggested template edits for ${host}"
  echo "  networking.hostName = \"${host}\";"
  echo "  networking.domain = \"${host}.lab.h4xx.io\";  # adjust domain"
  echo "  # Set disko device to a stable /dev/disk/by-id from above."
fi
