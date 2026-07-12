#!/usr/bin/env bash
set -euo pipefail

disk="/dev/nvme1n1"
partition="/dev/nvme1n1p1"
luks_uuid="f23e2488-c72e-402a-9bf7-7a2348861b87"
mapper="cryptdata"
vg_name="tux-data"
lv_name="data"
mountpoint="/data"

find_open_mapper() {
  local holder holder_name mapper_path

  for holder in /sys/class/block/nvme1n1p1/holders/*; do
    [ -e "$holder" ] || continue
    holder_name="$(basename "$holder")"
    for mapper_path in /dev/mapper/*; do
      [ -e "$mapper_path" ] || continue
      if [ "$(readlink -f "$mapper_path")" = "/dev/${holder_name}" ]; then
        printf '%s\n' "$mapper_path"
        return 0
      fi
    done
  done

  return 1
}

if [ "${1:-}" != "--destroy-existing-luks-payload" ]; then
  cat >&2 <<EOF
Refusing to continue without explicit confirmation.

This will create an LVM PV/VG/LV and ext4 filesystem inside:
  ${partition}

It keeps the existing LUKS container, but destroys any current payload inside it.

Run:
  sudo $0 --destroy-existing-luks-payload
EOF
  exit 2
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root." >&2
  exit 1
fi

actual_uuid="$(blkid -s UUID -o value "$partition")"
if [ "$actual_uuid" != "$luks_uuid" ]; then
  echo "Unexpected ${partition} UUID: ${actual_uuid}; expected ${luks_uuid}" >&2
  exit 1
fi

if ! lsblk -dn -o MODEL "$disk" | grep -q "Samsung SSD 980 PRO 2TB"; then
  echo "Unexpected disk model for ${disk}:" >&2
  lsblk -dn -o NAME,MODEL,SERIAL,SIZE "$disk" >&2
  exit 1
fi

if cryptsetup status "$mapper" >/dev/null 2>&1; then
  pv="/dev/mapper/${mapper}"
elif pv="$(find_open_mapper)"; then
  echo "Reusing already-open LUKS mapper ${pv}." >&2
else
  cryptsetup open "$partition" "$mapper"
  pv="/dev/mapper/${mapper}"
fi

if pvs "$pv" >/dev/null 2>&1; then
  echo "${pv} is already an LVM PV." >&2
else
  pvcreate "$pv"
fi

if vgs "$vg_name" >/dev/null 2>&1; then
  echo "VG ${vg_name} already exists." >&2
else
  vgcreate "$vg_name" "$pv"
fi

if lvs "/dev/${vg_name}/${lv_name}" >/dev/null 2>&1; then
  echo "LV /dev/${vg_name}/${lv_name} already exists." >&2
else
  lvcreate -l 100%FREE -n "$lv_name" "$vg_name"
fi

if blkid "/dev/${vg_name}/${lv_name}" >/dev/null 2>&1; then
  echo "/dev/${vg_name}/${lv_name} already has a filesystem." >&2
else
  mkfs.ext4 -L tux-data "/dev/${vg_name}/${lv_name}"
fi

mkdir -p "$mountpoint"
mount "$mountpoint"

echo "Provisioned and mounted /dev/${vg_name}/${lv_name} at ${mountpoint}."
