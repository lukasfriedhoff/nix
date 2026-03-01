#!/usr/bin/env bash
# Remove a libvirt VM/domain and optionally delete matching leftover volumes.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/vms/remove-qemu-vm.sh --name <vm-name> [options]

Safely cleans up a libvirt VM:
  - destroys the domain if running
  - undefines the domain (with --nvram when supported)
  - deletes leftover volumes matching the VM name prefix
  - handles directory-backed volumes (for example in a tmp pool)

Defaults:
  connect URI: qemu:///system
  pools:       all libvirt pools
  volume match prefixes: <name>, <name>-

Options:
  --name <name>                 Domain/VM name (required)
  --connect <uri>               Libvirt URI (default: qemu:///system)
  --pool <pool>                 Storage pool to scan/delete from (repeatable)
  --prefix <prefix>             Volume name prefix to match (repeatable)
  --contains <text>             Volume name substring to match (repeatable)
  --volume <name>               Exact volume name to delete (repeatable)
  --keep-volumes                Only remove domain/NVRAM; keep storage volumes
  --dry-run                     Print actions without executing
  -h, --help                    Show this help

Examples:
  scripts/vms/remove-qemu-vm.sh --name srv3
  scripts/vms/remove-qemu-vm.sh --name srv3 --pool default --prefix srv3-
  scripts/vms/remove-qemu-vm.sh --name srv3 --pool tmp --contains srv3
  scripts/vms/remove-qemu-vm.sh --name srv3 --dry-run
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

print_cmd() {
  {
    printf '>> '
    printf '%q ' "$@"
    printf '\n'
  } >&2
}

run_cmd() {
  print_cmd "$@"
  if [[ "$dry_run" == true ]]; then
    return 0
  fi
  "$@"
}

contains_value() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

pool_target_path() {
  local pool="$1"
  virsh --connect "$connect_uri" pool-dumpxml "$pool" 2>/dev/null | awk -F'[<>]' '
    /<target>/ { in_target = 1 }
    in_target && /<path>/ { print $3; exit }
    /<\/target>/ { in_target = 0 }
  '
}

remove_dir_volume_data() {
  local pool="$1"
  local vol="$2"
  local path target

  path="$(virsh --connect "$connect_uri" vol-path "$vol" "$pool" 2>/dev/null || true)"
  target="$(pool_target_path "$pool")"

  if [[ -z "$path" || -z "$target" ]]; then
    echo ">> Warning: cannot resolve safe path for dir volume ${pool}:${vol}; skipping recursive delete" >&2
    return 1
  fi

  target="${target%/}"
  if [[ "$path" == "/" || "$path" == "$target" ]]; then
    echo ">> Warning: refusing to remove unsafe dir path '${path}' for ${pool}:${vol}" >&2
    return 1
  fi

  case "$path" in
    "$target"/*) ;;
    *)
      echo ">> Warning: path '${path}' is outside pool target '${target}', skipping ${pool}:${vol}" >&2
      return 1
      ;;
  esac

  run_cmd rm -rf -- "$path"
  run_cmd virsh --connect "$connect_uri" pool-refresh "$pool"
  return 0
}

delete_volume() {
  local pool="$1"
  local vol="$2"
  local vol_type=""

  vol_type="$(
    virsh --connect "$connect_uri" vol-info "$vol" "$pool" 2>/dev/null | awk '/^Type:/ { print $2; exit }'
  )"

  if [[ "$vol_type" == "dir" ]]; then
    if run_cmd virsh --connect "$connect_uri" vol-delete "$vol" "$pool"; then
      return 0
    fi
    echo ">> Volume ${pool}:${vol} is directory-backed; attempting recursive cleanup"
    if remove_dir_volume_data "$pool" "$vol"; then
      if virsh --connect "$connect_uri" vol-info "$vol" "$pool" >/dev/null 2>&1; then
        run_cmd virsh --connect "$connect_uri" vol-delete "$vol" "$pool" || true
      fi
    fi
    return 0
  fi

  run_cmd virsh --connect "$connect_uri" vol-delete "$vol" "$pool"
}

list_pool_volumes() {
  local pool="$1"
  local listing
  if ! listing="$(virsh --connect "$connect_uri" vol-list "$pool" 2>/dev/null)"; then
    echo ">> Warning: failed to list volumes in pool '${pool}'" >&2
    return 0
  fi
  # Keep compatibility with virsh versions that do not support `vol-list --name`.
  printf '%s\n' "$listing" \
    | awk '
        BEGIN { in_table = 0 }
        /^-+$/ { in_table = 1; next }
        in_table && NF >= 1 { print $1 }
      '
}

name=""
connect_uri="${LIBVIRT_URI:-qemu:///system}"
pools=()
prefixes=()
contains=()
exact_volumes=()
keep_volumes=false
dry_run=false
user_set_pools=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      name="$2"
      shift 2
      ;;
    --connect)
      connect_uri="$2"
      shift 2
      ;;
    --pool)
      pools+=("$2")
      user_set_pools=true
      shift 2
      ;;
    --prefix)
      prefixes+=("$2")
      shift 2
      ;;
    --contains)
      contains+=("$2")
      shift 2
      ;;
    --volume)
      exact_volumes+=("$2")
      shift 2
      ;;
    --keep-volumes)
      keep_volumes=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$name" ]] || die "--name is required"
need_cmd virsh

# Discover pools automatically unless --pool was provided.
if [[ "$user_set_pools" == false ]]; then
  discovered_pools=false
  while IFS= read -r pool; do
    [[ -n "$pool" ]] || continue
    pools+=("$pool")
    discovered_pools=true
  done < <(virsh --connect "$connect_uri" pool-list --all --name 2>/dev/null || true)
  if [[ "$discovered_pools" == false ]]; then
    echo ">> Warning: failed to enumerate libvirt pools; falling back to pool 'default'" >&2
  fi
fi

if [[ "${#pools[@]}" -eq 0 ]]; then
  pools=("default")
fi

# Remove duplicate pools.
uniq_pools=()
for pool in "${pools[@]}"; do
  if [[ -n "$pool" ]] && ! contains_value "$pool" "${uniq_pools[@]}"; then
    uniq_pools+=("$pool")
  fi
done
pools=("${uniq_pools[@]}")

if [[ "${#prefixes[@]}" -eq 0 ]]; then
  prefixes=("$name" "${name}-")
fi

echo ">> Cleanup target: name=${name} connect=${connect_uri}"

if virsh --connect "$connect_uri" dominfo "$name" >/dev/null 2>&1; then
  state="$(virsh --connect "$connect_uri" domstate "$name" 2>/dev/null || true)"
  if [[ "$state" != "shut off" && -n "$state" ]]; then
    run_cmd virsh --connect "$connect_uri" destroy "$name"
  fi

  if ! run_cmd virsh --connect "$connect_uri" undefine "$name" --nvram; then
    run_cmd virsh --connect "$connect_uri" undefine "$name"
  fi
else
  echo ">> Domain not found (skipping undefine): ${name}"
fi

if [[ "$keep_volumes" == true ]]; then
  echo ">> Keeping volumes (--keep-volumes)"
  exit 0
fi

to_delete=()

for pool in "${pools[@]}"; do
  if ! virsh --connect "$connect_uri" pool-refresh "$pool" >/dev/null 2>&1; then
    echo ">> Warning: failed to refresh pool '${pool}' before scan" >&2
  fi

  while IFS= read -r vol; do
    [[ -n "$vol" ]] || continue
    matched=false
    for pfx in "${prefixes[@]}"; do
      if [[ "$vol" == "${pfx}"* ]]; then
        key="${pool}:${vol}"
        if ! contains_value "$key" "${to_delete[@]}"; then
          to_delete+=("$key")
        fi
        matched=true
        break
      fi
    done
    if [[ "$matched" == true ]]; then
      continue
    fi

    for needle in "${contains[@]}"; do
      if [[ -n "$needle" && "$vol" == *"$needle"* ]]; then
        key="${pool}:${vol}"
        if ! contains_value "$key" "${to_delete[@]}"; then
          to_delete+=("$key")
        fi
        break
      fi
    done
  done < <(list_pool_volumes "$pool" || true)

  for vol in "${exact_volumes[@]}"; do
    if virsh --connect "$connect_uri" vol-info "$vol" "$pool" >/dev/null 2>&1; then
      key="${pool}:${vol}"
      if ! contains_value "$key" "${to_delete[@]}"; then
        to_delete+=("$key")
      fi
    fi
  done
done

if [[ "${#to_delete[@]}" -eq 0 ]]; then
  echo ">> No matching volumes found"
  exit 0
fi

echo ">> Deleting ${#to_delete[@]} volume(s)"
for item in "${to_delete[@]}"; do
  pool="${item%%:*}"
  vol="${item#*:}"
  delete_volume "$pool" "$vol"
done

echo ">> Cleanup complete."
