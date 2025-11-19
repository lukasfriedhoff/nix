#!/usr/bin/env bash
set -euo pipefail

out_dir="/tmp/power-metrics-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out_dir"

echo "Writing reports to $out_dir"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd powertop
require_cmd turbostat
require_cmd intel_gpu_top
require_cmd nvidia-smi
require_cmd iotop
require_cmd ps
require_cmd grep

if [[ $EUID -ne 0 ]]; then
  echo "This script requires sudo/root privileges. Please re-run with sudo." >&2
  exit 1
fi

echo "Collecting battery snapshot..."
if command -v upower >/dev/null 2>&1; then
  battery_dev="$(upower -e | grep -m1 battery || true)"
  if [[ -n "$battery_dev" ]]; then
    upower -i "$battery_dev" > "$out_dir/battery.txt"
  fi
fi

if compgen -G "/sys/class/power_supply/BAT*/uevent" >/dev/null; then
  for bat in /sys/class/power_supply/BAT*/uevent; do
    echo "# $(basename "$(dirname "$bat")")" >> "$out_dir/battery.txt"
    cat "$bat" >> "$out_dir/battery.txt"
    echo >> "$out_dir/battery.txt"
  done
fi

echo "Collecting powertop sample (60s)..."
powertop --time=60 --html "$out_dir/powertop.html" >/dev/null
powertop --time=60 --csv="$out_dir/powertop.csv" >/dev/null 2>&1 || true

echo "Collecting turbostat sample..."
turbostat --Summary --quiet \
  --show Busy%,Bzy_MHz,PkgWatt,CorWatt,CoreTmp \
  --interval 1 --num_iterations 120 > "$out_dir/turbostat.txt"

echo "Collecting intel_gpu_top sample..."
intel_gpu_top -o "$out_dir/intel-gpu-top.txt" -s 1000 -p >/dev/null 2>&1 &
intel_gpu_pid=$!
sleep 30
kill "$intel_gpu_pid" >/dev/null 2>&1 || true

echo "Collecting NVIDIA snapshots..."
nvidia-smi --query-gpu=timestamp,power.draw,clocks.sm,clocks.mem,memory.used,memory.total \
  --format=csv,noheader > "$out_dir/nvidia-power.csv" 2>/dev/null || true
nvidia-smi pmon -c 30 -s u > "$out_dir/nvidia-processes.txt" 2>/dev/null || true
nvidia-smi --query-compute-apps=pid,process_name,used_memory \
  --format=csv,noheader > "$out_dir/nvidia-compute-apps.txt" 2>/dev/null || true

echo "Collecting NVIDIA dmon sample..."
nvidia-smi dmon -s pucv -o DT -c 60 > "$out_dir/nvidia-dmon.txt"

echo "Collecting IO sample..."
iotop -b -n 5 > "$out_dir/iotop.txt"

echo "Capturing top CPU and memory processes..."
ps -eo pid,comm,%cpu,%mem,etimes --sort=-%cpu | head -n 25 > "$out_dir/top-cpu.txt"
ps -eo pid,comm,%mem,%cpu,etimes --sort=-%mem | head -n 25 > "$out_dir/top-mem.txt"

echo "Reports ready under $out_dir"
