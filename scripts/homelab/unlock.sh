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
  --router <ssh-target>    Router whose DHCP lease table is consulted (read-only)
                           when the target does not answer or resolve; default:
                           $UNLOCK_ROUTER or mikrotikhiesfelder, `none` disables

Fallbacks (only without --target): when the configured target cannot be
resolved, libvirt leases are consulted for VMs; when it cannot be resolved or
does not answer, the router's DHCP leases for <host> (host-name or comment)
are probed for the initrd SSH listener — the initrd has no bond/bridge, so a
reservation bound to the runtime MAC leaves it on a pool address.

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
# Site router (MikroTik RouterOS) whose DHCP lease table is read — never
# written — when the configured target is unreachable. The default is the
# Hiesfelder L009 that serves the physical homelab hosts.
router="${UNLOCK_ROUTER:-mikrotikhiesfelder}"
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
    --router)
      router="$2"
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

# Resolve the effective ssh settings of $target (alias expansion via ssh -G)
# into target_ssh_host / target_ssh_user / target_ssh_port / target_ssh_identity.
read_target_ssh_config() {
  local ssh_key ssh_val
  target_ssh_host="$target"
  target_ssh_user=""
  target_ssh_port=""
  target_ssh_identity=""
  command -v ssh >/dev/null 2>&1 || return 0
  while read -r ssh_key ssh_val _; do
    case "$ssh_key" in
      hostname) target_ssh_host="$ssh_val" ;;
      user) target_ssh_user="$ssh_val" ;;
      port) target_ssh_port="$ssh_val" ;;
      identityfile)
        if [[ -z "$target_ssh_identity" ]]; then
          target_ssh_identity="$(expand_home_path "$ssh_val")"
        fi
        ;;
    esac
  done < <(ssh -G "$target" 2>/dev/null || true)
}

# Point the unlock at a discovered address, keeping the alias' user, port and
# identity unless they were given explicitly.
apply_fallback_target() {
  local ip="$1"
  target="${target_ssh_user:-root}@${ip}"
  if [[ -z "$port" ]]; then
    port="${target_ssh_port:-2222}"
  fi
  if [[ -z "$identity_file" && -n "$target_ssh_identity" && -f "$target_ssh_identity" ]]; then
    identity_file="$target_ssh_identity"
    if ! has_option_prefix "IdentitiesOnly" ${ssh_extra_opts[@]+"${ssh_extra_opts[@]}"}; then
      ssh_extra_opts+=("IdentitiesOnly=yes")
    fi
  fi
}

resolve_via_libvirt_if_needed() {
  local force_lookup="${1:-false}"

  read_target_ssh_config

  if [[ "$target_ssh_host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    return
  fi

  if [[ "$force_lookup" != "true" ]] && getent ahostsv4 "$target_ssh_host" >/dev/null 2>&1; then
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

  apply_fallback_target "$lease_ip"

  echo ">> DNS lookup for ${target_ssh_host} failed; using libvirt lease ${target} (port ${port})"
}

# Read-only lookup on the site router: the address of every DHCP lease whose
# host-name or comment mentions the host, dynamic (pool) leases first — that
# is where an initrd lands when the MAC it presents has no reservation.
# RouterOS 7 syntax: `print terse where …` (no `brief`); the ssh banner noise
# (WARNING / openssh / "store now, decrypt later") is filtered out.
router_lease_candidates() {
  local query
  for query in "host-name=\"${host}\"" "comment~\"${host}\""; do
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$router" \
      "/ip dhcp-server lease print terse where ${query}" 2>/dev/null \
      | grep -vE 'WARNING|openssh|store now' || true
  done | awk '
    {
      dynamic = ($2 == "D")
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^address=[0-9.]+$/) {
          ip = substr($i, 9)
          if (ip in seen) continue
          seen[ip] = 1
          if (dynamic) pool[++np] = ip; else fixed[++nf] = ip
        }
      }
    }
    END {
      for (i = 1; i <= np; i++) print pool[i]
      for (i = 1; i <= nf; i++) print fixed[i]
    }'
}

# Retarget the unlock at whichever router lease for the host answers on the
# initrd SSH port. Leaves target/port untouched when nothing answers.
resolve_via_router_leases() {
  local probe_port ip candidates skip

  if [[ "$router" == "none" ]]; then
    return
  fi
  if ! command -v ssh-keyscan >/dev/null 2>&1; then
    return
  fi

  read_target_ssh_config
  probe_port="${port:-${target_ssh_port:-2222}}"
  # Addresses the configured target already resolves to were just tried.
  skip="$(getent ahostsv4 "$target_ssh_host" 2>/dev/null | awk '{print $1}' | sort -u || true)"

  echo ">> Looking up DHCP leases for ${host} on ${router} (read-only)"
  candidates="$(router_lease_candidates)"
  if [[ -z "$candidates" ]]; then
    echo ">> ${router} lists no DHCP lease mentioning ${host}" >&2
    return
  fi

  for ip in $candidates; do
    if grep -qx -- "$ip" <<<"$skip"; then
      continue
    fi
    if ssh-keyscan -p "$probe_port" -T 3 "$ip" 2>/dev/null | grep -q .; then
      echo ">> Lease ${ip} answers on port ${probe_port}; using it as the unlock target"
      apply_fallback_target "$ip"
      return
    fi
    echo ">> Lease ${ip} does not answer on port ${probe_port}, skipping"
  done
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

# Try the libvirt (unresolved names only) and router-lease fallbacks; retry
# the unlock when either produced a new target. Returns 1 when nothing did.
retry_with_fallback() {
  local reason="$1"
  local old_target="$target" old_port="$port"

  if [[ "$reason" == "unresolved" ]]; then
    resolve_via_libvirt_if_needed true
  fi
  if [[ "$target" == "$old_target" && "$port" == "$old_port" ]]; then
    resolve_via_router_leases
  fi
  if [[ "$target" == "$old_target" && "$port" == "$old_port" ]]; then
    return 1
  fi

  echo ">> Retrying unlock using fallback target ${target}${port:+ (port ${port})}"
  if ! unlock_once "$err_file"; then
    die "unlock SSH failed for ${target}. Check key auth and verify the host is booting from the installed disk (not the installer ISO)."
  fi
}

err_file="$(mktemp)"
trap 'rm -f "$err_file"' EXIT
if ! unlock_once "$err_file"; then
  if grep -Eqi "Connection refused" "$err_file"; then
    die "connection to ${target} refused: the host is on the network but no \
initrd SSH listener is running — it either booted past the unlock prompt \
already or is not in the initrd (check the console)."
  elif grep -Eqi "timed out|No route to host" "$err_file"; then
    if [[ "$target_overridden" == true ]] || ! retry_with_fallback unreachable; then
      die "cannot reach ${target}: nothing answers at that address. The initrd \
either never started, its NIC has no link, or it came up on a DHCP pool \
address that ${router} does not list for ${host} — check the console, the \
ethernet link LED and the router's lease table before retrying."
    fi
  elif [[ "$target_overridden" == false ]] && grep -Eqi "Could not resolve hostname|Name or service not known|Temporary failure in name resolution" "$err_file"; then
    if ! retry_with_fallback unresolved; then
      die "unlock SSH failed for ${target}. Could not resolve hostname and neither a libvirt lease nor a router lease for ${host} was found."
    fi
  else
    die "unlock SSH failed for ${target}. Check key auth and verify the VM is booting from the installed disk (not the installer ISO)."
  fi
fi

echo ">> Passphrase delivered to ${target}:${remote_path}"
