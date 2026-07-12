#!/usr/bin/env bash
set -euo pipefail

data_lv="/dev/tux-data/data"
data_mount="/data"

declare -a migrations=(
  "/home/lukasf/media:/data/media:/mnt/tux-old-media"
  "/home/lukasf/Nextcloud:/data/nextcloud:/mnt/tux-old-nextcloud"
  "/home/lukasf/nextcloud-prod:/data/nextcloud-prod:/mnt/tux-old-nextcloud-prod"
  "/home/lukasf/nextcloud-testing:/data/nextcloud-testing:/mnt/tux-old-nextcloud-testing"
)

usage() {
  cat >&2 <<EOF
Usage:
  sudo $0 --migrate-to-data-subfolders

This migrates:
  /home/lukasf/media              -> /data/media
  /home/lukasf/Nextcloud          -> /data/nextcloud
  /home/lukasf/nextcloud-prod     -> /data/nextcloud-prod
  /home/lukasf/nextcloud-testing  -> /data/nextcloud-testing

It keeps the existing source filesystems intact for rollback.
EOF
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root." >&2
    exit 1
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

mount_data() {
  mkdir -p "$data_mount"
  if ! findmnt -rn "$data_mount" >/dev/null 2>&1; then
    mount "$data_lv" "$data_mount"
  fi
}

prepare_target() {
  local target="$1"

  mkdir -p "$target"
  chown lukasf:users "$target"
  chmod 0750 "$target"
}

sync_tree() {
  local source="$1"
  local target="$2"

  rsync -aHAXS --numeric-ids --info=progress2 "${source}/" "${target}/"
}

is_already_migrated() {
  local source="$1"
  local target="$2"
  local target_subpath="${target#"$data_mount"}"
  local mounted_source

  mounted_source="$(findmnt -rn --target "$source" -o SOURCE 2>/dev/null || true)"
  [ "$mounted_source" = "${data_lv}[${target_subpath}]" ] \
    || [ "$mounted_source" = "/dev/mapper/tux--data-data[${target_subpath}]" ]
}

is_exact_mountpoint() {
  findmnt -rn --mountpoint "$1" >/dev/null 2>&1
}

assert_not_busy() {
  local source="$1"

  if lsof +f -- "$source" >/tmp/tux-migration-lsof.out 2>/dev/null; then
    if [ "$(wc -l < /tmp/tux-migration-lsof.out)" -gt 1 ]; then
      echo "${source} is still in use; close these processes before FINAL-SYNC:" >&2
      cat /tmp/tux-migration-lsof.out >&2
      exit 1
    fi
  fi
}

for_each_migration() {
  local migration source target old_mount

  for migration in "${migrations[@]}"; do
    IFS=: read -r source target old_mount <<< "$migration"
    "$@" "$source" "$target" "$old_mount"
  done
}

prepare_one_target() {
  local source="$1"
  local target="$2"

  if [ ! -d "$source" ]; then
    echo "Source directory does not exist: ${source}" >&2
    exit 1
  fi

  prepare_target "$target"
}

initial_sync_one() {
  local source="$1"
  local target="$2"

  if is_already_migrated "$source" "$target"; then
    echo "Skipping ${source}; already bind-mounted from ${target}." >&2
    return 0
  fi

  echo "Initial sync ${source} -> ${target}..." >&2
  sync_tree "$source" "$target"
}

final_sync_one() {
  local source="$1"
  local target="$2"
  local old_mount="$3"
  local old_device=""
  local final_source="$source"

  if is_already_migrated "$source" "$target"; then
    echo "Skipping ${source}; already bind-mounted from ${target}." >&2
    return 0
  fi

  assert_not_busy "$source"

  if is_exact_mountpoint "$source"; then
    old_device="$(findmnt -rn -o SOURCE --mountpoint "$source")"
    umount "$source"

    mkdir -p "$old_mount"
    mount "$old_device" "$old_mount"
    mount -o remount,ro "$old_mount"
    final_source="$old_mount"
  fi

  echo "Final sync ${source} -> ${target}..." >&2
  sync_tree "$final_source" "$target"

  if [ -n "$old_device" ]; then
    umount "$old_mount"
  fi

  mount --bind "$target" "$source"

  if [ -n "$old_device" ]; then
    echo "Rollback source for ${source}: ${old_device}" >&2
  else
    echo "Rollback source for ${source}: original files hidden under bind mount on /home." >&2
  fi
}

if [ "${1:-}" != "--migrate-to-data-subfolders" ]; then
  usage
  exit 2
fi

require_root
require_command rsync
require_command lsof

if [ ! -e "$data_lv" ]; then
  echo "${data_lv} does not exist. Run scripts/tux/provision-nvme1-data-lvm.sh first." >&2
  exit 1
fi

mount_data
for_each_migration prepare_one_target
for_each_migration initial_sync_one

cat >&2 <<'EOF'

Initial copy is complete.

Close applications using media and Nextcloud sync folders now.
The script will unmount exact filesystem mountpoints, remount old sources
read-only under /mnt, run a final sync, then bind-mount /data subfolders on the
live paths.

EOF

read -r -p "Type FINAL-SYNC to continue: " confirmation
if [ "$confirmation" != "FINAL-SYNC" ]; then
  echo "Aborted before switching mounts." >&2
  exit 2
fi

for_each_migration final_sync_one

echo "Migration complete." >&2
