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

if [[ $EUID -ne 0 ]]; then
  echo "This script requires sudo/root privileges. Please re-run with sudo." >&2
  exit 1
fi

echo "Collecting powertop sample (60s)..."
powertop --time=60 --html "$out_dir/powertop.html" >/dev/null

echo "Collecting turbostat sample..."
turbostat --Summary --quiet \
  --show Busy%,Bzy_MHz,PkgWatt,CorWatt,CoreTmp \
  --interval 1 --num_iterations 120 > "$out_dir/turbostat.txt"

echo "Collecting intel_gpu_top sample..."
intel_gpu_top -o "$out_dir/intel-gpu-top.txt" -s 1000 -p >/dev/null 2>&1 &
intel_gpu_pid=$!
sleep 30
kill "$intel_gpu_pid" >/dev/null 2>&1 || true

echo "Collecting NVIDIA dmon sample..."
nvidia-smi dmon -s pucv -o DT -c 60 > "$out_dir/nvidia-dmon.txt"

echo "Collecting IO sample..."
iotop -b -n 5 > "$out_dir/iotop.txt"

echo "Reports ready under $out_dir"
