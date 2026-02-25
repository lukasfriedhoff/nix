#!/usr/bin/env bash
# Create a new libvirt/QEMU VM (cloud image, ISO install, or netboot kernel+initrd).

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/vms/new-qemu-vm.sh --name <vm-name> [options]

Defaults:
  mode:        cloud
  connect URI: qemu:///system
  machine:     q35
  firmware:    UEFI
  memory:      4096 MiB
  vcpus:       2
  disk-size:   40 GiB

Modes:
  cloud  Import a cloud image and attach a cloud-init seed ISO.
  iso    Boot from an installer ISO.
  netboot  Boot installer kernel+initrd with explicit kernel args.

Required per mode:
  cloud: --image <path-or-url>
  iso:   --iso <path-or-url>
  netboot: --kernel <path-or-url> --initrd <path-or-url> --kernel-args '<cmdline>'

General options:
  --name <name>                 VM/domain name (required)
  --mode cloud|iso|netboot      Create flow (default: cloud)
  --memory <MiB>                Memory in MiB (default: 4096)
  --vcpus <count>               vCPU count (default: 2)
  --disk-size <GiB>             Disk size in GiB (default: 40)
  --disk-path <path>            Target disk path (default: /var/lib/libvirt/images/<name>.qcow2)
  --disk-format qcow2|raw       Disk format (default: qcow2)
  --disk-bus virtio|scsi|sata   Disk bus (default: virtio)
  --disk-serial <serial>        Disk serial (default: <name>-root)
  --osinfo <id>                 virt-install osinfo (default: generic)
  --wait <seconds>              virt-install --wait value (default: 0)

Connection options:
  --connect <uri>               Libvirt URI (default: qemu:///system)
  --remote <user@host>          Convenience shortcut for qemu+ssh://<user@host>/system
  --remote-port <port>          SSH port for --remote

Firmware/machine options:
  --machine <type>              QEMU machine type (default: q35)
  --uefi                        Use UEFI firmware (default)
  --bios                        Use BIOS/legacy firmware

Network options:
  --network <libvirt-net>       Attach to libvirt network (default: default)
  --bridge <ifname>             Attach to bridge (mutually exclusive with --network)

Cloud mode options:
  --image <path-or-url>         Cloud image path or URL
  --user-data <file>            cloud-init user-data
  --meta-data <file>            cloud-init meta-data (default auto-generated)
  --network-config <file>       cloud-init network-config (optional)
  --seed-path <path>            Seed ISO path (default: /var/lib/libvirt/images/<name>-seed.iso)

ISO mode options:
  --iso <path-or-url>           Installer ISO path or URL

Netboot mode options:
  --kernel <path-or-url>        Installer kernel path or URL
  --initrd <path-or-url>        Installer initrd path or URL
  --kernel-args <string>        Kernel command line (required for netboot mode)
  --cmdline <string>            Alias for --kernel-args

Behavior options:
  --autostart                   Enable libvirt autostart
  --no-start                    Define VM but do not start it
  --force                       Undefine existing domain and overwrite disk/seed files
  --dry-run                     Print actions without executing
  --verbose                     Print resolved settings before execution
  -h, --help                    Show this help

Examples:
  scripts/vms/new-qemu-vm.sh \
    --name ubuntu-dev-01 \
    --mode cloud \
    --image https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img \
    --user-data docs/examples/cloud-init/ubuntu/user-data.yaml \
    --meta-data docs/examples/cloud-init/ubuntu/meta-data.yaml

  scripts/vms/new-qemu-vm.sh \
    --name srv3-installer \
    --mode iso \
    --iso https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso

  scripts/vms/new-qemu-vm.sh \
    --name ubuntu-netboot-01 \
    --mode netboot \
    --kernel https://releases.ubuntu.com/24.04/netboot/amd64/linux \
    --initrd https://releases.ubuntu.com/24.04/netboot/amd64/initrd \
    --kernel-args "ip=dhcp url=https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso autoinstall ds=nocloud-net;s=http://10.0.0.1/cloud-init/"

  scripts/vms/new-qemu-vm.sh \
    --remote root@srv1.lab.h4xx.io \
    --name ubuntu-ci-01 \
    --mode cloud \
    --image /var/lib/libvirt/images/jammy-server-cloudimg-amd64.img
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

is_url() {
  [[ "$1" =~ ^https?:// ]]
}

escape_install_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//,/\\,}"
  printf '%s\n' "$value"
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

run_remote() {
  local remote_cmd="$1"
  echo ">> ssh ${remote_ssh_target} ${remote_cmd}" >&2
  if [[ "$dry_run" == true ]]; then
    return 0
  fi
  "${ssh_cmd[@]}" "${remote_ssh_target}" "${remote_cmd}"
}

remote_has_file() {
  local path="$1"
  "${ssh_cmd[@]}" "${remote_ssh_target}" "test -f $(printf '%q' "$path")"
}

remote_remove_file() {
  local path="$1"
  run_remote "rm -f $(printf '%q' "$path")"
}

sanitize_url_basename() {
  local url="$1"
  local base="${url##*/}"
  base="${base%%\?*}"
  if [[ -z "$base" ]]; then
    base="download.img"
  fi
  printf '%s\n' "$base"
}

download_local() {
  local url="$1"
  local dest="$2"
  run_cmd mkdir -p "$(dirname "$dest")"
  if command -v curl >/dev/null 2>&1; then
    run_cmd curl -fL --retry 3 --retry-delay 1 -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    run_cmd wget -O "$dest" "$url"
  else
    die "need curl or wget to download ${url}"
  fi
}

download_remote() {
  local url="$1"
  local dest="$2"
  local qdest
  local qurl
  qdest="$(printf '%q' "$dest")"
  qurl="$(printf '%q' "$url")"
  run_remote "mkdir -p $(printf '%q' "$(dirname "$dest")")"
  run_remote "if command -v curl >/dev/null 2>&1; then curl -fL --retry 3 --retry-delay 1 -o ${qdest} ${qurl}; elif command -v wget >/dev/null 2>&1; then wget -O ${qdest} ${qurl}; else echo 'error: need curl or wget on remote host' >&2; exit 1; fi"
}

copy_local_to_remote() {
  local src="$1"
  local dest="$2"
  run_remote "mkdir -p $(printf '%q' "$(dirname "$dest")")"
  print_cmd "${scp_cmd[@]}" "$src" "${remote_ssh_target}:$dest"
  if [[ "$dry_run" == true ]]; then
    return 0
  fi
  "${scp_cmd[@]}" "$src" "${remote_ssh_target}:$dest"
}

resolve_media_path() {
  local source="$1"
  local remote_cache_dir="$2"
  local local_cache_dir="$3"

  if [[ "$remote_mode" == true ]]; then
    if is_url "$source"; then
      local remote_dest="${remote_cache_dir}/$(sanitize_url_basename "$source")"
      if [[ "$force" == true ]]; then
        remote_remove_file "$remote_dest"
      fi
      if ! remote_has_file "$remote_dest" || [[ "$force" == true ]]; then
        download_remote "$source" "$remote_dest"
      fi
      printf '%s\n' "$remote_dest"
      return
    fi

    if [[ -f "$source" ]]; then
      local remote_dest="${remote_cache_dir}/$(basename "$source")"
      if [[ "$force" == true ]]; then
        remote_remove_file "$remote_dest"
      fi
      if ! remote_has_file "$remote_dest" || [[ "$force" == true ]]; then
        copy_local_to_remote "$source" "$remote_dest"
      fi
      printf '%s\n' "$remote_dest"
      return
    fi

    # Assume caller supplied a path that exists on the remote libvirt host.
    if [[ "$dry_run" == false ]] && ! remote_has_file "$source"; then
      die "remote file does not exist: ${source}"
    fi
    printf '%s\n' "$source"
    return
  fi

  if is_url "$source"; then
    local local_dest="${local_cache_dir}/$(sanitize_url_basename "$source")"
    if [[ "$force" == true ]]; then
      run_cmd rm -f "$local_dest"
    fi
    if [[ ! -f "$local_dest" ]] || [[ "$force" == true ]]; then
      download_local "$source" "$local_dest"
    fi
    printf '%s\n' "$local_dest"
    return
  fi

  [[ -f "$source" ]] || die "file does not exist: ${source}"
  printf '%s\n' "$source"
}

build_seed_iso() {
  local out_iso="$1"
  local user_data_file="$2"
  local meta_data_file="$3"
  local network_cfg_file="$4"

  if command -v cloud-localds >/dev/null 2>&1; then
    local cloud_localds_cmd=(cloud-localds)
    if [[ -n "$network_cfg_file" ]]; then
      cloud_localds_cmd+=(--network-config "$network_cfg_file")
    fi
    cloud_localds_cmd+=("$out_iso" "$user_data_file" "$meta_data_file")
    run_cmd "${cloud_localds_cmd[@]}"
    return
  fi

  local mkiso_bin=""
  if command -v genisoimage >/dev/null 2>&1; then
    mkiso_bin="genisoimage"
  elif command -v mkisofs >/dev/null 2>&1; then
    mkiso_bin="mkisofs"
  fi
  [[ -n "$mkiso_bin" ]] || die "need cloud-localds, genisoimage, or mkisofs for cloud-init seed creation"

  local stage_dir
  stage_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir:-}" "${stage_dir}"' EXIT

  cp "$user_data_file" "${stage_dir}/user-data"
  cp "$meta_data_file" "${stage_dir}/meta-data"
  if [[ -n "$network_cfg_file" ]]; then
    cp "$network_cfg_file" "${stage_dir}/network-config"
  fi

  if [[ -n "$network_cfg_file" ]]; then
    run_cmd "$mkiso_bin" -output "$out_iso" -volid cidata -joliet -rock "${stage_dir}/user-data" "${stage_dir}/meta-data" "${stage_dir}/network-config"
  else
    run_cmd "$mkiso_bin" -output "$out_iso" -volid cidata -joliet -rock "${stage_dir}/user-data" "${stage_dir}/meta-data"
  fi

  rm -rf "$stage_dir"
  trap 'rm -rf "${tmp_dir:-}"' EXIT
}

name=""
mode="cloud"
memory_mib="${VM_DEFAULT_MEMORY_MIB:-4096}"
vcpus="${VM_DEFAULT_VCPUS:-2}"
disk_size_gib="40"
disk_path=""
disk_format="qcow2"
disk_bus="virtio"
disk_serial=""
seed_path=""
image_source=""
iso_source=""
kernel_source=""
initrd_source=""
kernel_args=""
user_data=""
meta_data=""
network_config=""
osinfo="${VM_DEFAULT_OSINFO:-generic}"
wait_seconds="0"

connect_uri="${LIBVIRT_URI:-qemu:///system}"
remote_target=""
remote_port=""

network_name="${VM_DEFAULT_NETWORK:-default}"
bridge_name=""

machine_type="q35"
use_efi=true

graphics="none"
autostart=false
start_now=true
force=false
dry_run=false
verbose=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      name="$2"
      shift 2
      ;;
    --mode)
      mode="$2"
      shift 2
      ;;
    --memory)
      memory_mib="$2"
      shift 2
      ;;
    --vcpus)
      vcpus="$2"
      shift 2
      ;;
    --disk-size)
      disk_size_gib="$2"
      shift 2
      ;;
    --disk-path)
      disk_path="$2"
      shift 2
      ;;
    --disk-format)
      disk_format="$2"
      shift 2
      ;;
    --disk-bus)
      disk_bus="$2"
      shift 2
      ;;
    --disk-serial)
      disk_serial="$2"
      shift 2
      ;;
    --seed-path)
      seed_path="$2"
      shift 2
      ;;
    --image)
      image_source="$2"
      shift 2
      ;;
    --iso)
      iso_source="$2"
      shift 2
      ;;
    --kernel)
      kernel_source="$2"
      shift 2
      ;;
    --initrd)
      initrd_source="$2"
      shift 2
      ;;
    --kernel-args|--cmdline)
      kernel_args="$2"
      shift 2
      ;;
    --user-data)
      user_data="$2"
      shift 2
      ;;
    --meta-data)
      meta_data="$2"
      shift 2
      ;;
    --network-config)
      network_config="$2"
      shift 2
      ;;
    --osinfo)
      osinfo="$2"
      shift 2
      ;;
    --wait)
      wait_seconds="$2"
      shift 2
      ;;
    --connect)
      connect_uri="$2"
      shift 2
      ;;
    --remote)
      remote_target="$2"
      shift 2
      ;;
    --remote-port)
      remote_port="$2"
      shift 2
      ;;
    --network)
      network_name="$2"
      shift 2
      ;;
    --bridge)
      bridge_name="$2"
      shift 2
      ;;
    --machine)
      machine_type="$2"
      shift 2
      ;;
    --uefi)
      use_efi=true
      shift
      ;;
    --bios)
      use_efi=false
      shift
      ;;
    --graphics)
      graphics="$2"
      shift 2
      ;;
    --autostart)
      autostart=true
      shift
      ;;
    --no-start)
      start_now=false
      shift
      ;;
    --force)
      force=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --verbose)
      verbose=true
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
case "$mode" in
  cloud|iso|netboot) ;;
  *) die "--mode must be cloud, iso, or netboot" ;;
esac
case "$disk_format" in
  qcow2|raw) ;;
  *) die "--disk-format must be qcow2 or raw" ;;
esac
case "$disk_bus" in
  virtio|scsi|sata) ;;
  *) die "--disk-bus must be virtio, scsi, or sata" ;;
esac
case "$graphics" in
  none|vnc|spice) ;;
  *) die "--graphics must be none, vnc, or spice" ;;
esac

if [[ -n "$bridge_name" && -n "$network_name" && "$network_name" != "default" ]]; then
  die "use either --bridge or --network"
fi
if [[ -n "$bridge_name" ]]; then
  network_name=""
fi

if [[ -n "$remote_target" ]]; then
  if [[ "$connect_uri" != "qemu:///system" && "$connect_uri" != "${LIBVIRT_URI:-qemu:///system}" ]]; then
    die "do not combine --remote with an explicit --connect"
  fi
  if [[ -n "$remote_port" ]]; then
    connect_uri="qemu+ssh://${remote_target}:${remote_port}/system"
  else
    connect_uri="qemu+ssh://${remote_target}/system"
  fi
fi

remote_mode=false
remote_ssh_target=""
remote_ssh_port=""
if [[ "$connect_uri" =~ ^qemu\+ssh://(([^@/]+)@)?([^:/]+)(:([0-9]+))?/system$ ]]; then
  remote_mode=true
  remote_ssh_user="${BASH_REMATCH[2]:-}"
  remote_ssh_host="${BASH_REMATCH[3]}"
  remote_ssh_port="${BASH_REMATCH[5]:-}"
  remote_ssh_target="${remote_ssh_user:+${remote_ssh_user}@}${remote_ssh_host}"
fi

if [[ "$mode" == "cloud" ]]; then
  [[ -n "$image_source" ]] || die "cloud mode requires --image"
  [[ "$disk_format" == "qcow2" ]] || die "cloud mode currently requires --disk-format qcow2"
fi
if [[ "$mode" == "iso" ]]; then
  [[ -n "$iso_source" ]] || die "iso mode requires --iso"
  if is_url "$iso_source" && [[ ! "$iso_source" =~ \.iso([?#].*)?$ ]]; then
    die "iso mode expects an ISO URL; netboot tarballs are not supported by this script"
  fi
fi
if [[ "$mode" == "netboot" ]]; then
  [[ -n "$kernel_source" ]] || die "netboot mode requires --kernel"
  [[ -n "$initrd_source" ]] || die "netboot mode requires --initrd"
  [[ -n "$kernel_args" ]] || die "netboot mode requires --kernel-args (or --cmdline)"
fi

if [[ -z "$disk_path" ]]; then
  disk_path="/var/lib/libvirt/images/${name}.${disk_format}"
fi
if [[ -z "$disk_serial" ]]; then
  disk_serial="${name}-root"
fi
if [[ -z "$seed_path" ]]; then
  seed_path="/var/lib/libvirt/images/${name}-seed.iso"
fi

need_cmd virt-install
need_cmd virsh
need_cmd qemu-img
if [[ "$remote_mode" == true ]]; then
  need_cmd ssh
  need_cmd scp
fi

ssh_cmd=(ssh -o BatchMode=yes)
scp_cmd=(scp -o BatchMode=yes)
if [[ -n "$remote_ssh_port" ]]; then
  ssh_cmd+=(-p "$remote_ssh_port")
  scp_cmd+=(-P "$remote_ssh_port")
fi

local_cache_dir="${TMPDIR:-/tmp}/new-qemu-vm-cache"
remote_cache_dir="/var/lib/libvirt/images/cache"
libvirt_boot_dir="/var/lib/libvirt/boot"

if [[ "$verbose" == true ]]; then
  cat <<SETTINGS
Resolved settings:
  name:          ${name}
  mode:          ${mode}
  connect_uri:   ${connect_uri}
  remote_mode:   ${remote_mode}
  machine:       ${machine_type}
  firmware:      $( [[ "$use_efi" == true ]] && echo UEFI || echo BIOS )
  memory MiB:    ${memory_mib}
  vcpus:         ${vcpus}
  disk path:     ${disk_path}
  disk size GiB: ${disk_size_gib}
  disk format:   ${disk_format}
  disk bus:      ${disk_bus}
  disk serial:   ${disk_serial}
SETTINGS
fi

if virsh --connect "$connect_uri" dominfo "$name" >/dev/null 2>&1; then
  if [[ "$force" == true ]]; then
    run_cmd virsh --connect "$connect_uri" destroy "$name" || true
    run_cmd virsh --connect "$connect_uri" undefine "$name" --nvram || run_cmd virsh --connect "$connect_uri" undefine "$name"
  else
    die "domain already exists: ${name} (use --force to replace)"
  fi
fi

if [[ "$remote_mode" == true ]]; then
  run_remote "mkdir -p $(printf '%q' "$(dirname "$disk_path")")"
  if [[ "$mode" == "cloud" ]]; then
    run_remote "mkdir -p $(printf '%q' "$(dirname "$seed_path")")"
  fi
  if [[ "$mode" == "netboot" ]]; then
    if ! run_remote "mkdir -p $(printf '%q' "$libvirt_boot_dir")"; then
      die "failed to create ${libvirt_boot_dir} on remote host; required for netboot kernel/initrd staging"
    fi
  fi
else
  run_cmd mkdir -p "$(dirname "$disk_path")"
  if [[ "$mode" == "cloud" ]]; then
    run_cmd mkdir -p "$(dirname "$seed_path")"
  fi
  if [[ "$mode" == "netboot" ]]; then
    if ! run_cmd mkdir -p "$libvirt_boot_dir"; then
      die "failed to create ${libvirt_boot_dir}; required for netboot kernel/initrd staging"
    fi
  fi
fi

if [[ "$remote_mode" == true ]]; then
  if [[ "$dry_run" == false ]] && remote_has_file "$disk_path"; then
    if [[ "$force" == true ]]; then
      remote_remove_file "$disk_path"
    else
      die "disk path already exists on remote host: ${disk_path}"
    fi
  fi
  if [[ "$mode" == "cloud" && "$dry_run" == false ]] && remote_has_file "$seed_path"; then
    if [[ "$force" == true ]]; then
      remote_remove_file "$seed_path"
    else
      die "seed ISO path already exists on remote host: ${seed_path}"
    fi
  fi
else
  if [[ -e "$disk_path" ]]; then
    if [[ "$force" == true ]]; then
      run_cmd rm -f "$disk_path"
    else
      die "disk path already exists: ${disk_path}"
    fi
  fi
  if [[ "$mode" == "cloud" && -e "$seed_path" ]]; then
    if [[ "$force" == true ]]; then
      run_cmd rm -f "$seed_path"
    else
      die "seed ISO path already exists: ${seed_path}"
    fi
  fi
fi

if [[ -n "$network_name" ]]; then
  if ! net_info="$(virsh --connect "$connect_uri" net-info "$network_name" 2>/dev/null)"; then
    die "libvirt network not found: ${network_name}"
  fi
  if [[ "$dry_run" == false ]] && [[ ! "$net_info" =~ Active:[[:space:]]+yes ]]; then
    run_cmd virsh --connect "$connect_uri" net-start "$network_name"
  fi
fi

disk_source=""
seed_iso_local=""
iso_path=""
kernel_path=""
initrd_path=""
install_kernel_args=""
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

if [[ "$mode" == "cloud" ]]; then
  disk_source="$(resolve_media_path "$image_source" "$remote_cache_dir" "$local_cache_dir")"

  if [[ -z "$user_data" ]]; then
    user_data="${tmp_dir}/user-data"
    cat > "$user_data" <<'YAML'
#cloud-config
users:
  - default
chpasswd:
  expire: false
ssh_pwauth: false
YAML
  elif [[ ! -f "$user_data" ]]; then
    die "user-data file not found: ${user_data}"
  fi

  if [[ -z "$meta_data" ]]; then
    meta_data="${tmp_dir}/meta-data"
    cat > "$meta_data" <<META
instance-id: ${name}
local-hostname: ${name}
META
  elif [[ ! -f "$meta_data" ]]; then
    die "meta-data file not found: ${meta_data}"
  fi

  if [[ -n "$network_config" && ! -f "$network_config" ]]; then
    die "network-config file not found: ${network_config}"
  fi

  if [[ "$remote_mode" == true ]]; then
    seed_iso_local="${tmp_dir}/${name}-seed.iso"
  else
    seed_iso_local="$seed_path"
  fi

  build_seed_iso "$seed_iso_local" "$user_data" "$meta_data" "$network_config"

  if [[ "$remote_mode" == true ]]; then
    copy_local_to_remote "$seed_iso_local" "$seed_path"
    run_remote "qemu-img create -f qcow2 -F qcow2 -b $(printf '%q' "$disk_source") $(printf '%q' "$disk_path") ${disk_size_gib}G"
  else
    run_cmd qemu-img create -f qcow2 -F qcow2 -b "$disk_source" "$disk_path" "${disk_size_gib}G"
  fi
else
  if [[ "$mode" == "iso" ]]; then
    iso_path="$(resolve_media_path "$iso_source" "$remote_cache_dir" "$local_cache_dir")"
  else
    kernel_path="$(resolve_media_path "$kernel_source" "$remote_cache_dir" "$local_cache_dir")"
    initrd_path="$(resolve_media_path "$initrd_source" "$remote_cache_dir" "$local_cache_dir")"
    install_kernel_args="$(escape_install_value "$kernel_args")"
  fi
  if [[ "$remote_mode" == true ]]; then
    run_remote "qemu-img create -f $(printf '%q' "$disk_format") $(printf '%q' "$disk_path") ${disk_size_gib}G"
  else
    run_cmd qemu-img create -f "$disk_format" "$disk_path" "${disk_size_gib}G"
  fi
fi

virt_args=(
  virt-install
  --connect "$connect_uri"
  --name "$name"
  --memory "$memory_mib"
  --vcpus "$vcpus"
  --machine "$machine_type"
  --osinfo "$osinfo"
  --disk "path=${disk_path},format=${disk_format},bus=${disk_bus},serial=${disk_serial}"
  --rng /dev/urandom
  --graphics "$graphics"
  --console pty,target_type=serial
  --noautoconsole
  --wait "$wait_seconds"
  --print-xml
)

if [[ "$use_efi" == true ]]; then
  virt_args+=(--boot uefi)
fi

if [[ -n "$bridge_name" ]]; then
  virt_args+=(--network "bridge=${bridge_name},model=virtio")
else
  virt_args+=(--network "network=${network_name},model=virtio")
fi

if [[ "$mode" == "cloud" ]]; then
  virt_args+=(
    --import
    --disk "path=${seed_path},device=cdrom"
  )
elif [[ "$mode" == "iso" ]]; then
  virt_args+=(--cdrom "$iso_path")
else
  virt_args+=(--install "kernel=${kernel_path},initrd=${initrd_path},kernel_args=${install_kernel_args}")
fi

tmp_xml="${tmp_dir}/${name}.xml"
tmp_xml_raw="${tmp_dir}/${name}.xml.raw"
print_cmd "${virt_args[@]}"
if [[ "$dry_run" == false ]]; then
  "${virt_args[@]}" > "$tmp_xml_raw"

  # virt-install may emit multiple domain XML documents (install + post-install).
  # virsh define accepts exactly one, so take the first complete <domain>...</domain>.
  awk '
    /<domain[[:space:]>]/ { if (!in_doc) in_doc = 1 }
    in_doc { print }
    in_doc && /<\/domain>/ { exit }
  ' "$tmp_xml_raw" > "$tmp_xml"

  if [[ ! -s "$tmp_xml" ]]; then
    die "failed to extract domain XML from virt-install output"
  fi

  run_cmd virsh --connect "$connect_uri" define "$tmp_xml"

  if [[ "$autostart" == true ]]; then
    run_cmd virsh --connect "$connect_uri" autostart "$name"
  fi

  if [[ "$start_now" == true ]]; then
    run_cmd virsh --connect "$connect_uri" start "$name"
  fi
fi

cat <<SUMMARY

VM definition complete.
  Name:       ${name}
  Connect URI:${connect_uri}
  Disk:       ${disk_path}
SUMMARY
if [[ "$mode" == "cloud" ]]; then
  cat <<SUMMARY2
  Seed ISO:   ${seed_path}
SUMMARY2
elif [[ "$mode" == "iso" ]]; then
  cat <<SUMMARY2
  ISO:        ${iso_path}
SUMMARY2
else
  cat <<SUMMARY2
  Kernel:     ${kernel_path}
  Initrd:     ${initrd_path}
  Cmdline:    ${kernel_args}
SUMMARY2
fi

if [[ "$start_now" == true ]]; then
  cat <<NEXT

Next commands:
  virsh --connect ${connect_uri} dominfo ${name}
  virsh --connect ${connect_uri} console ${name}
NEXT
else
  cat <<NEXT

VM is defined but not started.
Start it with:
  virsh --connect ${connect_uri} start ${name}
NEXT
fi
