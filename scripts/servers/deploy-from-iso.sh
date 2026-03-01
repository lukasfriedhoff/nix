#!/usr/bin/env bash
# Deploy a flake host via nixos-anywhere from a live installer.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/servers/deploy-from-iso.sh <nixosConfiguration> <target> [options] [extra nixos-anywhere args...]

Examples:
  scripts/servers/deploy-from-iso.sh docker-host-01 root@10.7.5.5
  scripts/servers/deploy-from-iso.sh my-homelab-node root@192.168.42.15 --with-kexec
  scripts/servers/deploy-from-iso.sh srv1 root@10.1.30.12 --luks-secret secrets/profiles/personal/shared/luks/srv1.txt
  scripts/servers/deploy-from-iso.sh srv3 root@192.168.122.56 --identity ~/.ssh/srv3-personal-mgmt

This is a thin wrapper around nixos-anywhere. The first argument must match a nixosConfigurations.<name>
defined in the flake. The target is the SSH destination of the temporary installer environment.

Options:
  --luks-secret <sops-file>  Decrypt and pass LUKS key via --disk-encryption-keys.
  --age-key-secret <sops-file>
                             Decrypt and include host Age key at
                             /var/lib/sops-nix/age/keys.txt via
                             nixos-anywhere --extra-files. If omitted, defaults to
                             secrets/profiles/personal/servers/<host>/age.key when present.
  --identity <private-key>   SSH identity file for both preflight SSH and nixos-anywhere.
  --ssh-option <opt>         Extra SSH option (repeatable), e.g. --ssh-option IdentitiesOnly=yes
  --with-kexec               Include the kexec phase (default behavior skips kexec for ISO installs).
USAGE
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

config="$1"; target="$2"; shift 2
luks_secret=""
age_key_secret=""
identity_file=""
with_kexec=false
user_ssh_options=()
extra_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --luks-secret)
      luks_secret="$2"
      shift 2
      ;;
    --age-key-secret)
      age_key_secret="$2"
      shift 2
      ;;
    --identity)
      identity_file="$2"
      shift 2
      ;;
    --ssh-option)
      user_ssh_options+=("$2")
      shift 2
      ;;
    --with-kexec)
      with_kexec=true
      shift
      ;;
    -h|--help)
      usage; exit 0
      ;;
    *)
      extra_args+=("$1")
      shift
      ;;
  esac
done

flake=".#${config}"

tmp_key=""
tmp_age_key=""
tmp_extra_files=""
cleanup() {
  [[ -n "$tmp_key" && -f "$tmp_key" ]] && rm -f "$tmp_key"
  [[ -n "$tmp_age_key" && -f "$tmp_age_key" ]] && rm -f "$tmp_age_key"
  [[ -n "$tmp_extra_files" && -d "$tmp_extra_files" ]] && rm -rf "$tmp_extra_files"
}
trap cleanup EXIT

if [[ -n "$identity_file" ]] && [[ ! -f "$identity_file" ]]; then
  echo "error: identity file not found: ${identity_file}" >&2
  exit 2
fi

if [[ -n "$luks_secret" ]]; then
  if ! command -v sops >/dev/null 2>&1; then
    echo "error: sops not found but --luks-secret was provided" >&2
    exit 3
  fi
  tmp_key="$(mktemp)"
  SOPS_CONFIG="${SOPS_CONFIG:-${PWD}/.sops.yaml}" sops -d "$luks_secret" > "$tmp_key"
  extra_args+=(--disk-encryption-keys /tmp/luks.key "$tmp_key")
fi

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

if [[ -z "$age_key_secret" ]]; then
  default_age_key_secret="secrets/profiles/personal/servers/${config}/age.key"
  if [[ -f "$default_age_key_secret" ]]; then
    age_key_secret="$default_age_key_secret"
  fi
fi

if [[ -n "$age_key_secret" ]]; then
  if [[ ! -f "$age_key_secret" ]]; then
    echo "error: age key secret not found: ${age_key_secret}" >&2
    exit 7
  fi
  if ! command -v sops >/dev/null 2>&1; then
    echo "error: sops not found but --age-key-secret was provided/detected" >&2
    exit 8
  fi
  if has_option_prefix "--extra-files" "${extra_args[@]}"; then
    echo ">> Skipping auto Age key bootstrap because --extra-files is already set." >&2
    echo ">> Include /var/lib/sops-nix/age/keys.txt in your custom --extra-files payload." >&2
  else
    tmp_age_key="$(mktemp)"
    tmp_extra_files="$(mktemp -d)"
    SOPS_CONFIG="${SOPS_CONFIG:-${PWD}/.sops.yaml}" sops -d "$age_key_secret" > "$tmp_age_key"
    install -d -m 0700 "$tmp_extra_files/var/lib/sops-nix/age"
    install -m 0600 "$tmp_age_key" "$tmp_extra_files/var/lib/sops-nix/age/keys.txt"
    extra_args+=(--extra-files "$tmp_extra_files")
    echo ">> Including decrypted Age key from ${age_key_secret} via --extra-files"
  fi
fi

resolve_hardware_config_path() {
  local cfg_name="$1"
  local candidate
  local matches=()

  for scope in homelab personal work dacoso; do
    candidate="hosts/${scope}/${cfg_name}/hardware-configuration.nix"
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  while IFS= read -r candidate; do
    matches+=("$candidate")
  done < <(find hosts -type f -path "*/${cfg_name}/hardware-configuration.nix" 2>/dev/null | sort)

  if [[ "${#matches[@]}" -eq 1 ]]; then
    printf '%s\n' "${matches[0]}"
    return 0
  fi
  return 1
}

sanitize_hardware_config() {
  python3 -c 'import sys
lines = sys.stdin.read().splitlines()
out = []
skip = False
for line in lines:
    stripped = line.lstrip()
    if not skip and (stripped.startswith("fileSystems.") or stripped.startswith("swapDevices")):
        skip = True
    if not skip:
        out.append(line)
    if skip and line.strip() == "":
        skip = False
sanitized = "\n".join(out).strip()
if not sanitized:
    sanitized = "\n".join(lines).strip()
print(sanitized + ("\n" if sanitized else ""))'
}

default_ssh_options=(
  "StrictHostKeyChecking=no"
  "UserKnownHostsFile=/dev/null"
  "ConnectTimeout=5"
  "ConnectionAttempts=1"
)
ssh_options=("${default_ssh_options[@]}")
ssh_options+=("${user_ssh_options[@]}")

if [[ -n "$identity_file" ]] && ! has_option_prefix "IdentitiesOnly" "${ssh_options[@]}"; then
  ssh_options+=("IdentitiesOnly=yes")
fi

copy_host_keys=true
for arg in "${extra_args[@]}"; do
  if [[ "$arg" == "--copy-host-keys" ]]; then
    copy_host_keys=false
    break
  fi
done
if [[ "$copy_host_keys" == true ]]; then
  extra_args+=(--copy-host-keys)
fi

phases_already_set=false
for arg in "${extra_args[@]}"; do
  if [[ "$arg" == "--phases" || "$arg" == "--phases="* || "$arg" == "--kexec" ]]; then
    phases_already_set=true
    break
  fi
done
if [[ "$phases_already_set" == false ]]; then
  if [[ "$with_kexec" == true ]]; then
    extra_args+=(--phases kexec,disko,install,reboot)
  else
    extra_args+=(--phases disko,install,reboot)
  fi
fi

ssh_cmd=(ssh)
if [[ -n "$identity_file" ]]; then
  ssh_cmd+=(-i "$identity_file")
fi
for opt in "${ssh_options[@]}"; do
  ssh_cmd+=(-o "$opt")
done

anywhere_args=()
if [[ -n "$identity_file" ]]; then
  anywhere_args+=(-i "$identity_file")
fi
for opt in "${ssh_options[@]}"; do
  anywhere_args+=(--ssh-option "$opt")
done

echo ">> Deploying ${flake} to ${target}"
# Make sure initrd SSH host key exists on the installer so boot.initrd.network.ssh.hostKeys can read it.
"${ssh_cmd[@]}" "${target}" \
  "mkdir -p /etc/ssh && if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then ssh-keygen -t ed25519 -N '' -f /etc/ssh/ssh_host_ed25519_key; fi" || {
  echo "error: failed to create initrd SSH host key on target ${target}" >&2
  exit 4
}

if hw_path="$(resolve_hardware_config_path "$config")"; then
  if grep -q "Replace hosts/homelab/<name>/hardware-configuration.nix" "$hw_path"; then
    echo ">> Template hardware config detected at ${hw_path}; fetching from installer"
    raw_hw="$(
      "${ssh_cmd[@]}" "${target}" "nixos-generate-config --show-hardware-config"
    )" || {
      echo "error: failed to fetch hardware-configuration from target ${target}" >&2
      exit 5
    }

    if command -v python3 >/dev/null 2>&1; then
      sanitized_hw="$(printf '%s\n' "$raw_hw" | sanitize_hardware_config)"
    else
      sanitized_hw="$raw_hw"
    fi

    if [[ -z "${sanitized_hw//[[:space:]]/}" ]]; then
      echo "error: fetched hardware-configuration is empty; refusing to overwrite ${hw_path}" >&2
      exit 6
    fi

    printf '%s' "$sanitized_hw" > "$hw_path"
    echo ">> Wrote hardware config to ${hw_path}"
  fi
fi

export NIX_CONFIG="experimental-features = nix-command flakes"
nix run github:nix-community/nixos-anywhere -- \
  --flake "${flake}" \
  "${anywhere_args[@]}" \
  "${target}" \
  "${extra_args[@]}"
