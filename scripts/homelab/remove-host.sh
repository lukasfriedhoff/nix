#!/usr/bin/env bash
# Remove a homelab host and its related entries.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/homelab/remove-host.sh --host <short> [--keep-host-dir] [--delete-secrets]

Removes a personal homelab host:
  - deletes hosts/homelab/<host>/ (unless --keep-host-dir)
  - removes SSH key install + host entries (access + unlock) from resources/ssh/{keys.nix,hosts.nix}
  - removes disk inventory entries from resources/homelab/disks.nix
  - removes host (and orphaned cluster) entries from resources/homelab/ceph.nix
  - drops flake.nix entries (secretsByProfile + nixosConfigurations)
  - optionally deletes secrets/profiles/personal/servers/<host>/ plus shared LUKS/desktop mgmt keys when --delete-secrets is set
EOF
}

die() { echo "error: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

host=""
keep_host_dir=false
delete_secrets=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) host="$2"; shift 2;;
    --keep-host-dir) keep_host_dir=true; shift 1;;
    --delete-secrets) delete_secrets=true; shift 1;;
    -h|--help) usage; exit 0;;
    *) die "unknown argument: $1";;
  esac
done

[[ -n "$host" ]] || die "--host is required"

need_cmd git
need_cmd python3

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

host_dir="hosts/homelab/${host}"
if [[ -d "$host_dir" ]]; then
  if [[ "$keep_host_dir" == false ]]; then
    echo ">> Removing ${host_dir}"
    rm -rf -- "$host_dir"
  else
    echo ">> Keeping existing ${host_dir}"
  fi
else
  echo ">> Host dir not found (skipping): ${host_dir}"
fi

echo ">> Removing SSH key entry from resources/ssh/keys.nix (if present)"
python3 - "$host" "resources/ssh/keys.nix" <<'PY'
import sys, pathlib
host, path = sys.argv[1], pathlib.Path(sys.argv[2])
lines = path.read_text().splitlines(keepends=True)

def keep_block(block: list[str]) -> bool:
    joined = "".join(block)
    return f'secret = "ssh/{host}-personal-mgmt.priv";' not in joined

out = []
i = 0
while i < len(lines):
    line = lines[i]
    if line.lstrip().startswith("{"):
        block = [line]
        i += 1
        while i < len(lines):
            block.append(lines[i])
            if lines[i].lstrip().startswith("}"):
                i += 1
                break
            i += 1
        if keep_block(block):
            out.extend(block)
    else:
        out.append(line)
        i += 1

path.write_text("".join(out))
PY

echo ">> Removing SSH host entries (access + unlock) from resources/ssh/hosts/personal.nix (if present)"
python3 - "$host" "resources/ssh/hosts/personal.nix" <<'PY'
import sys, pathlib
host, path = sys.argv[1], pathlib.Path(sys.argv[2])
lines = path.read_text().splitlines(keepends=True)

start = next((i for i, l in enumerate(lines) if l.strip() == "["), None)
end = next((i for i, l in enumerate(lines) if l.strip() == "]"), None)
if start is None or end is None or end <= start:
    sys.exit("could not locate list in resources/ssh/hosts/personal.nix")

prefix = lines[: start + 1]
suffix = lines[end:]
body = lines[start + 1 : end]

out = []
i = 0
while i < len(body):
    line = body[i]
    if line.lstrip().startswith("{"):
        block = [line]
        i += 1
        while i < len(body):
            block.append(body[i])
            if body[i].lstrip().startswith("}"):
                i += 1
                break
            i += 1
        joined = "".join(block)
        if f'match = "{host}"' in joined or f'match = "unlock-{host}"' in joined:
            continue
        out.extend(block)
    else:
        out.append(line)
        i += 1

path.write_text("".join(prefix + out + suffix))
PY

echo ">> Removing host disk entries from resources/homelab/disks.nix (if present)"
python3 - "$host" "resources/homelab/disks.nix" <<'PY'
import re
import sys
from pathlib import Path

host, path = sys.argv[1], Path(sys.argv[2])
lines = path.read_text().splitlines(keepends=True)

out = []
i = 0
while i < len(lines):
    line = lines[i]
    if re.match(r'^\s*"[^"]+"\s*=\s*\{\s*$', line):
        block = [line]
        i += 1
        while i < len(lines):
            block.append(lines[i])
            if re.match(r'^\s*\};\s*$', lines[i]):
                i += 1
                break
            i += 1
        joined = "".join(block)
        if f'host = "{host}";' in joined:
            continue
        out.extend(block)
    else:
        out.append(line)
        i += 1

path.write_text("".join(out))
PY

echo ">> Removing host/cluster entries from resources/homelab/ceph.nix (if present)"
python3 - "$host" "resources/homelab/ceph.nix" <<'PY'
import re
import sys
from pathlib import Path

host, path = sys.argv[1], Path(sys.argv[2])
text = path.read_text()

line_index = [0]
for i, ch in enumerate(text):
    if ch == "\n":
        line_index.append(i + 1)

def line_col_to_offset(line_no: int) -> int:
    return line_index[line_no]

def block_bounds(marker: str):
    marker_pos = text.find(marker)
    if marker_pos < 0:
        return None
    open_pos = text.find("{", marker_pos)
    if open_pos < 0:
        return None
    depth = 0
    for i in range(open_pos, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return open_pos, i
    return None

def remove_attr_block(src: str, name: str):
    lines = src.splitlines(keepends=True)
    out = []
    i = 0
    removed_block = ""
    while i < len(lines):
        line = lines[i]
        m = re.match(r'^\s*([A-Za-z0-9._-]+)\s*=\s*\{\s*$', line)
        if m and m.group(1) == name:
            block = [line]
            depth = line.count("{") - line.count("}")
            i += 1
            while i < len(lines):
                block.append(lines[i])
                depth += lines[i].count("{") - lines[i].count("}")
                if depth <= 0:
                    i += 1
                    break
                i += 1
            removed_block = "".join(block)
            continue
        out.append(line)
        i += 1
    return "".join(out), removed_block

def find_host_cluster(src: str, host_name: str):
    lines = src.splitlines(keepends=True)
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r'^\s*([A-Za-z0-9._-]+)\s*=\s*\{\s*$', line)
        if m and m.group(1) == host_name:
            block = [line]
            depth = line.count("{") - line.count("}")
            i += 1
            while i < len(lines):
                block.append(lines[i])
                depth += lines[i].count("{") - lines[i].count("}")
                if depth <= 0:
                    break
                i += 1
            joined = "".join(block)
            cluster_match = re.search(r'cluster\s*=\s*"([^"]+)"\s*;', joined)
            return cluster_match.group(1) if cluster_match else None
        i += 1
    return None

def cluster_still_used(src: str, cluster_name: str):
    return re.search(rf'cluster\s*=\s*"{re.escape(cluster_name)}"\s*;', src) is not None

hosts_bounds = block_bounds("hosts = {")
clusters_bounds = block_bounds("clusters = {")
if hosts_bounds is None or clusters_bounds is None:
    path.write_text(text)
    sys.exit(0)

hosts_open, hosts_close = hosts_bounds
hosts_body = text[hosts_open + 1 : hosts_close]
cluster_name = find_host_cluster(hosts_body, host)
new_hosts_body, _ = remove_attr_block(hosts_body, host)
text = text[: hosts_open + 1] + new_hosts_body + text[hosts_close:]

if cluster_name:
    hosts_bounds = block_bounds("hosts = {")
    clusters_bounds = block_bounds("clusters = {")
    if hosts_bounds is not None and clusters_bounds is not None:
        hosts_open, hosts_close = hosts_bounds
        clusters_open, clusters_close = clusters_bounds
        hosts_body = text[hosts_open + 1 : hosts_close]
        if not cluster_still_used(hosts_body, cluster_name):
            clusters_body = text[clusters_open + 1 : clusters_close]
            new_clusters_body, _ = remove_attr_block(clusters_body, cluster_name)
            text = text[: clusters_open + 1] + new_clusters_body + text[clusters_close:]

path.write_text(text)
PY

echo ">> Removing flake.nix entries (secretsByProfile + nixosConfigurations) if present"
python3 - "$host" "flake.nix" <<'PY'
import sys, pathlib, re
host, path = sys.argv[1], pathlib.Path(sys.argv[2])
text = path.read_text()

# Remove any secretsByProfile entry for this host
text = re.sub(
    rf"\n\s*{re.escape(host)}\s*=\s*\{{\n(?:[^\{{\}}]*\n)*?\s*\}};\n",
    "\n",
    text,
    flags=re.MULTILINE,
)

# Remove any nixosConfigurations entry for this host
text = re.sub(
    rf"\n\s*{re.escape(host)}\s*=\s*mkNixosHost\s*\"{re.escape(host)}\"\s*\(\n(?:.*?\n)*?\s*\);\n",
    "\n",
    text,
    flags=re.MULTILINE,
)

path.write_text(text)
PY

# Purge host-specific Age recipient comments from .sops.yaml
python3 - "$host" ".sops.yaml" <<'PY'
import sys, pathlib
host, path = sys.argv[1], pathlib.Path(sys.argv[2])
text = path.read_text()
if host in text:
    new = "\n".join(line for line in text.splitlines() if host not in line)
    path.write_text(new + ("\n" if text.endswith("\n") else ""))
PY

if [[ "$delete_secrets" == true ]]; then
  secrets_dir="secrets/profiles/personal/servers/${host}"
  if [[ -d "$secrets_dir" ]]; then
    echo ">> Deleting secrets dir ${secrets_dir}"
    rm -rf -- "$secrets_dir"
  else
    echo ">> Secrets dir not found (skipping): ${secrets_dir}"
  fi

  # Remove desktop-common management key copies
  desk_priv="secrets/profiles/personal/desktops/common/ssh/${host}-personal-mgmt.priv"
  desk_pub="secrets/profiles/personal/desktops/common/ssh/${host}-personal-mgmt.pub"
  for f in "$desk_priv" "$desk_pub"; do
    if [[ -f "$f" ]]; then
      echo ">> Deleting ${f}"
      rm -f -- "$f"
    else
      echo ">> Desktop secret not found (skipping): $f"
    fi
  done

  shared_luks="secrets/profiles/personal/shared/luks/${host}.txt"
  if [[ -f "$shared_luks" ]]; then
    echo ">> Deleting ${shared_luks}"
    rm -f -- "$shared_luks"
  else
    echo ">> Shared LUKS secret not found (skipping): ${shared_luks}"
  fi
else
  echo ">> Secrets dir kept (use --delete-secrets to remove): secrets/profiles/personal/servers/${host}"
fi

echo ">> Removal complete."
