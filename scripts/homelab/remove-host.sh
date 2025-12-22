#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/homelab/remove-host.sh --host <short> [--keep-host-dir] [--delete-secrets]

Removes a personal homelab host:
  - deletes hosts/homelab/<host>/ (unless --keep-host-dir)
  - removes SSH key install + host entries (access + unlock) from resources/ssh/{keys.nix,hosts.nix}
  - drops flake.nix entries (secretsByProfile + nixosConfigurations)
  - optionally deletes secrets/profiles/personal/servers/<host>/ when --delete-secrets is set
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
else
  echo ">> Secrets dir kept (use --delete-secrets to remove): secrets/profiles/personal/servers/${host}"
fi

echo ">> Removal complete."
