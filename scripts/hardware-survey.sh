#!/usr/bin/env bash
set -euo pipefail

# Gather a comprehensive hardware snapshot for troubleshooting slow machines.
# Usage: ./hardware-survey.sh [output_dir]
# If no output directory is provided, files are written to /tmp/hardware-survey-<timestamp>.

out_dir="${1:-/tmp/hardware-survey-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$out_dir"

echo "Writing hardware survey to $out_dir"

log_section() {
  printf '\n==== %s ====' "$1"
  printf '\n\n'
}

# Turn a label into a safe filename fragment
sanitize_label() {
  local label="$1"
  local safe="${label// /-}"
  safe="${safe//\//-}"
  safe="${safe//[^A-Za-z0-9_.-]/-}"
  echo "$safe"
}

declare -a missing_cmds=()
declare -A missing_seen=()
declare -A cmd_packages=(
  [lspci]=pciutils
  [lsusb]=usbutils
  [smartctl]=smartmontools
  [ip]=iproute2
  [sensors]=lm-sensors
  [dmidecode]=dmidecode
)

run_command() {
  local label="$1"
  shift
  local cmd=("$@")
  local file="$out_dir/$(sanitize_label "$label").txt"

  # The command may be multi-word (e.g. "sh -c"), so check the first token.
  if ! command -v "${cmd[0]}" >/dev/null 2>&1; then
    printf 'Skipping %s (missing %s)\n' "$label" "${cmd[0]}" >>"$out_dir/skipped.txt"
    if [[ -z "${missing_seen[${cmd[0]}]:-}" ]]; then
      missing_cmds+=("${cmd[0]}")
      missing_seen["${cmd[0]}"]=1
    fi
    return
  fi

  log_section "$label" >>"$file"
  {
    "${cmd[@]}"
  } >>"$file" 2>&1 || true
}

echo "Collecting OS + kernel details..."
{
  log_section "OS Release"
  if [[ -f /etc/os-release ]]; then
    cat /etc/os-release
  fi

  log_section "Kernel"
  uname -a

  log_section "Uptime"
  uptime
} >"$out_dir/system.txt"

run_command "CPU" lscpu
run_command "CPU Info" cat /proc/cpuinfo
run_command "Memory" cat /proc/meminfo
run_command "PCI Devices" lspci -nnk
run_command "USB Devices" lsusb
run_command "Block Devices" lsblk -O
run_command "Disks + Partitions" lsblk -f
run_command "Disk Usage" df -h
run_command "SMART Devices" smartctl --scan
run_command "SMART Details" bash -c 'if command -v smartctl >/dev/null 2>&1; then for dev in $(smartctl --scan | awk "{print $1}"); do echo "# $dev"; smartctl -a "$dev"; echo; done; else echo "smartctl not installed"; fi'
run_command "Network Interfaces" ip -br addr
run_command "Network Links" ip -br link
run_command "Network Routes" ip route
run_command "Sensors" sensors
run_command "Firmware/BIOS" dmidecode
run_command "Kernel Messages" dmesg
run_command "Top Devices From dmesg" bash -c 'dmesg | egrep -i "(firmware|microcode|thermal|error)" || true'

log_section "Summary" >"$out_dir/README.txt"
echo "Collected hardware information under $out_dir" >>"$out_dir/README.txt"
echo "Include this directory in support requests for slow-device troubleshooting." >>"$out_dir/README.txt"

if [[ ${#missing_cmds[@]} -gt 0 ]]; then
  log_section "Missing tools" >>"$out_dir/README.txt"
  printf 'Some utilities were unavailable while collecting data. Installing them will fill in the skipped sections:\n' >>"$out_dir/README.txt"
  for cmd in "${missing_cmds[@]}"; do
    pkg="${cmd_packages[$cmd]:-$cmd}"
    printf -- "- %s (try installing: %s)\n" "$cmd" "$pkg" >>"$out_dir/README.txt"
  done
fi

cat <<'HELP' >>"$out_dir/README.txt"

Optional commands (run manually if skipped above):
- sudo sensors-detect       # Populate sensor modules before rerunning
- sudo smartctl -t short /dev/sdX  # Replace sdX with each disk
- sudo ethtool <iface>      # Detailed NIC settings
HELP

echo "Done. Attach $out_dir when asking for performance help."
