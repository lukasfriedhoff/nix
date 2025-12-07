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

echo ">> Removing SSH host entries (access + unlock) from resources/ssh/hosts.nix (if present)"
python3 - "$host" "resources/ssh/hosts.nix" <<'PY'
import sys, pathlib
host, path = sys.argv[1], pathlib.Path(sys.argv[2])
lines = path.read_text().splitlines(keepends=True)

start = next((i for i, l in enumerate(lines) if "hosts = [" in l), None)
end = None
if start is not None:
    end = next((i for i in range(start, len(lines)) if lines[i].strip() == "];"), None)
if start is None or end is None:
    sys.exit("could not locate hosts list in resources/ssh/hosts.nix")

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
import sys, pathlib
host, path = sys.argv[1], pathlib.Path(sys.argv[2])
lines = path.read_text().splitlines(keepends=True)

def remove_entry(lines, block_start, entry_prefix, end_pred, use_parens=False):
    try:
        start_idx = next(i for i, l in enumerate(lines) if block_start in l)
    except StopIteration:
        return lines
    try:
        end_idx = next(i for i in range(start_idx + 1, len(lines)) if end_pred(lines[i]))
    except StopIteration:
        return lines

    prefix = lines[: start_idx + 1]
    suffix = lines[end_idx:]
    body = lines[start_idx + 1 : end_idx]

    out = []
    i = 0
    while i < len(body):
        line = body[i]
        if line.strip().startswith(entry_prefix):
            depth = line.count("{") - line.count("}")
            paren = line.count("(") - line.count(")")
            i += 1
            while i < len(body):
                depth += body[i].count("{") - body[i].count("}")
                paren += body[i].count("(") - body[i].count(")")
                i += 1
                if use_parens:
                    if depth <= 0 and paren <= 0 and body[i - 1].strip().endswith(");"):
                        break
                else:
                    if depth <= 0:
                        break
            continue
        out.append(line)
        i += 1

    return prefix + out + suffix

lines = remove_entry(
    lines,
    "secretsByProfile = {",
    f"{host} =",
    lambda l: l.strip() == "};",
    use_parens=False,
)

lines = remove_entry(
    lines,
    "nixosConfigurations = {",
    f"{host} =",
    lambda l: l.strip() == "};",
    use_parens=True,
)

path.write_text("".join(lines))
PY

if [[ "$delete_secrets" == true ]]; then
  secrets_dir="secrets/profiles/personal/servers/${host}"
  if [[ -d "$secrets_dir" ]]; then
    echo ">> Deleting secrets dir ${secrets_dir}"
    rm -rf -- "$secrets_dir"
  else
    echo ">> Secrets dir not found (skipping): ${secrets_dir}"
  fi
else
  echo ">> Secrets dir kept (use --delete-secrets to remove): secrets/profiles/personal/servers/${host}"
fi

echo ">> Removal complete."
