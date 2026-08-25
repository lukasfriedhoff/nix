#!/usr/bin/env bash
# Decrypt and stream a LUKS passphrase to the initrd unlock target.

set -euo pipefail

# Prefer Nix-provided Bash on macOS (default /bin/bash is 3.2; empty-array
# expansion under `set -u` errors there).
if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
  for candidate in \
    /run/current-system/sw/bin/bash \
    "/etc/profiles/per-user/${USER:-}/bin/bash"; do
    if [[ -x "$candidate" ]]; then
      exec "$candidate" "$0" "$@"
    fi
  done
fi

. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/homelab/unlock.sh <host> [options] [<secret-path> [<remote-path>]]

Decrypts the LUKS passphrase (SOPS-encrypted) and streams it to the initrd
SSH listener for the given host, writing the passphrase to the target path
(default: /crypt-ramfs/passphrase) with mode 600 so the boot process can continue.

Defaults:
  secret-path: <nix-secrets>/secrets/profiles/personal/shared/luks/<host>.txt
               (nix-secrets checkout: ../nix-secrets, override with NIX_SECRETS_DIR)
  ssh target:  unlock-<host> (defined in resources/ssh/hosts/personal.nix)
  remote-path: /crypt-ramfs/passphrase

Options:
  --secret <path>          Override secret path
  --target <ssh-target>    Override SSH target (e.g. root@192.168.122.30)
  --remote-path <path>     Override remote passphrase path
  --identity <keyfile>     SSH identity file
  --port <port>            SSH port (useful with --target root@IP, usually 2222)
  --ssh-option <opt>       Additional SSH option (repeatable; passed as -o <opt>)

Examples:
  scripts/homelab/unlock.sh srv3
  scripts/homelab/unlock.sh srv3 --target root@192.168.122.30 --port 2222 --identity ~/.ssh/personal/ci
EOF
}

has_option_prefix() {
  local needle="$1"
  shift
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "${needle}" || "$arg" == "${needle}="* ]]; then
      return 0
    fi
  done
  return 1
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" || $# -lt 1 ]]; then
  usage
  [[ $# -lt 1 ]] && exit 1 || exit 0
fi

host="$1"
shift

secret=""
target="unlock-${host}"
target_overridden=false
remote_path="/crypt-ramfs/passphrase"
identity_file=""
port=""
ssh_extra_opts=()
positionals=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --secret)
      secret="$2"
      shift 2
      ;;
    --target)
      target="$2"
      target_overridden=true
      shift 2
      ;;
    --remote-path)
      remote_path="$2"
      shift 2
      ;;
    --identity)
      identity_file="$2"
      shift 2
      ;;
    --port)
      port="$2"
      shift 2
      ;;
    --ssh-option)
      ssh_extra_opts+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      positionals+=("$1")
      shift
      ;;
  esac
done

if [[ "${#positionals[@]}" -gt 0 ]]; then
  secret="${positionals[0]}"
fi
if [[ "${#positionals[@]}" -gt 1 ]]; then
  remote_path="${positionals[1]}"
fi
if [[ "${#positionals[@]}" -gt 2 ]]; then
  die "too many positional arguments"
fi

if [[ -z "$secret" ]]; then
  secrets_dir="$(secrets_root)"
  secret="${secrets_dir}/secrets/profiles/personal/shared/luks/${host}.txt"
fi

if [[ ! -f "$secret" ]]; then
  die "secret not found: $secret"
fi

expand_home_path() {
  local p="$1"
  if [[ "$p" == "~/"* ]]; then
    # Quoted pattern: unquoted ~/ is itself tilde-expanded inside ${p#...},
    # so the prefix never matches and the strip becomes a no-op.
    printf "%s/%s" "$HOME" "${p#"~/"}"
  elif [[ "$p" == "~" ]]; then
    printf "%s" "$HOME"
  else
    printf "%s" "$p"
  fi
}

resolve_via_libvirt_if_needed() {
  local force_lookup="${1:-false}"
  local ssh_host="$target"
  local ssh_user=""
  local ssh_port=""
  local ssh_identity=""
  local ssh_key ssh_val

  if command -v ssh >/dev/null 2>&1; then
    while read -r ssh_key ssh_val _; do
      case "$ssh_key" in
        hostname) ssh_host="$ssh_val" ;;
        user) ssh_user="$ssh_val" ;;
        port) ssh_port="$ssh_val" ;;
        identityfile)
          if [[ -z "$ssh_identity" ]]; then
            ssh_identity="$(expand_home_path "$ssh_val")"
          fi
          ;;
      esac
    done < <(ssh -G "$target" 2>/dev/null || true)
  fi

  if [[ "$ssh_host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    return
  fi

  if [[ "$force_lookup" != "true" ]] && getent ahostsv4 "$ssh_host" >/dev/null 2>&1; then
    return
  fi

  if ! command -v virsh >/dev/null 2>&1; then
    return
  fi

  local lease_ip
  # `|| true` keeps set -e/pipefail from silently killing the script when
  # the host is not a libvirt domain (physical hosts end up here whenever
  # DNS is unavailable).
  lease_ip="$(
    virsh --connect qemu:///system domifaddr "$host" --source lease 2>/dev/null \
      | awk '/ipv4/ {sub(/\/.*/, "", $4); print $4; exit}' || true
  )"

  if [[ -z "$lease_ip" ]]; then
    return
  fi

  target="${ssh_user:-root}@${lease_ip}"
  if [[ -z "$port" ]]; then
    if [[ -n "$ssh_port" ]]; then
      port="$ssh_port"
    else
      port="2222"
    fi
  fi
  if [[ -z "$identity_file" && -n "$ssh_identity" && -f "$ssh_identity" ]]; then
    identity_file="$ssh_identity"
  fi

  echo ">> DNS lookup for ${ssh_host} failed; using libvirt lease ${target} (port ${port})"
}

if [[ "$target_overridden" == false ]]; then
  resolve_via_libvirt_if_needed
fi

if [[ -n "$identity_file" ]]; then
  identity_file="$(expand_home_path "$identity_file")"
  if [[ ! -f "$identity_file" ]]; then
    die "identity file not found: $identity_file"
  fi
  if ! has_option_prefix "IdentitiesOnly" ${ssh_extra_opts[@]+"${ssh_extra_opts[@]}"}; then
    ssh_extra_opts+=("IdentitiesOnly=yes")
  fi
fi

# sops -d reads its metadata from the file itself; the config only matters
# when we resolved the secret out of the nix-secrets checkout.
if [[ -z "${SOPS_CONFIG:-}" && -n "${secrets_dir:-}" ]]; then
  SOPS_CONFIG="${secrets_dir}/.sops.yaml"
fi
if [[ -n "${SOPS_CONFIG:-}" ]]; then
  export SOPS_CONFIG
fi
echo ">> Unlocking ${host} via ${target} using ${secret} -> ${remote_path}"

build_ssh_cmd() {
  local opt
  ssh_cmd=(ssh)
  default_ssh_opts=(
    "BatchMode=yes"
    "PreferredAuthentications=publickey"
    "PasswordAuthentication=no"
    "KbdInteractiveAuthentication=no"
    "NumberOfPasswordPrompts=0"
  )
  while IFS= read -r opt; do
    default_ssh_opts+=("$opt")
  done < <(ssh_base_opts)
  if [[ -n "$identity_file" ]]; then
    ssh_cmd+=(-i "$identity_file")
  fi
  if [[ -n "$port" ]]; then
    ssh_cmd+=(-p "$port")
  fi
  for opt in "${default_ssh_opts[@]}"; do
    ssh_cmd+=(-o "$opt")
  done
  for opt in ${ssh_extra_opts[@]+"${ssh_extra_opts[@]}"}; do
    ssh_cmd+=(-o "$opt")
  done
}

unlock_once() {
  local err_file="$1"
  build_ssh_cmd
  if sops -d "$secret" | tr -d '\r\n' | "${ssh_cmd[@]}" "$target" "umask 077; install -m 600 /dev/stdin '${remote_path}'" 2>"$err_file"; then
    return 0
  fi
  cat "$err_file" >&2
  return 1
}

err_file="$(mktemp)"
trap 'rm -f "$err_file"' EXIT
if ! unlock_once "$err_file"; then
  if grep -Eqi "timed out|No route to host" "$err_file"; then
    die "cannot reach ${target}: the host has no network presence. The initrd \
either never started or its NIC has no link — check the console and the \
ethernet link LED before retrying."
  fi
  if grep -Eqi "Connection refused" "$err_file"; then
    die "connection to ${target} refused: the host is on the network but no \
initrd SSH listener is running — it either booted past the unlock prompt \
already or is not in the initrd (check the console)."
  fi
  if [[ "$target_overridden" == false ]] && grep -Eqi "Could not resolve hostname|Name or service not known|Temporary failure in name resolution" "$err_file"; then
    old_target="$target"
    old_port="$port"
    resolve_via_libvirt_if_needed true
    if [[ "$target" != "$old_target" || "$port" != "$old_port" ]]; then
      echo ">> Retrying unlock using fallback target ${target}${port:+ (port ${port})}"
      if ! unlock_once "$err_file"; then
        die "unlock SSH failed for ${target}. Check key auth and verify the VM is booting from the installed disk (not the installer ISO)."
      fi
    else
      die "unlock SSH failed for ${target}. Could not resolve hostname and no libvirt lease fallback was found."
    fi
  else
    die "unlock SSH failed for ${target}. Check key auth and verify the VM is booting from the installed disk (not the installer ISO)."
  fi
fi

echo ">> Passphrase delivered to ${target}:${remote_path}"
