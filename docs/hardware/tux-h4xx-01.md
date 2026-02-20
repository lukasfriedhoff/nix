# tux-h4xx-01 Hardware Inventory

Source: `lspci -vvvv` captured on the TUXEDO InfinityBook Pro 16 Gen8 (Raptor Lake-P).

## System Overview

- **Platform**: Tongfang / TUXEDO InfinityBook Pro 16 Gen8
- **CPU / PCH**: Intel Raptor Lake-P 6P+8E cores with Alder Lake PCH
- **Chipset devices**:
  - Host bridge: Intel Raptor Lake-P DRAM Controller
  - Multiple PCIe root ports (Thunderbolt 4 capable)
  - Intel Dynamic Platform & Thermal Framework, MEI, SMBus, SPI, GNA accelerator
- **IOMMU groups**: 0–17 active, suitable for virtualization / passthrough.

## Graphics

| Device | Bus | Driver | Notes |
| --- | --- | --- | --- |
| Intel Iris Xe Graphics (Raptor Lake-P) | 00:02.0 | `i915` | Primary iGPU, 16 MB BAR, 256 MB VRAM aperture. |
| NVIDIA GeForce RTX 4070 Max-Q (AD106M) | 01:00.0 | `nvidia` | Discrete GPU with 8 GB VRAM (`Region1`), Optimus offload ready. |

## Display / Input

- Thunderbolt 4 root ports at 00:07.* provide external display + USB4.
- Intel Alder Lake PCH USB 3.2 controller at 00:14.0 (`xhci_hcd`).
- Additional TB4 USB controller 00:0d.* for USB4 devices.
- Intel LPSS I²C controllers (touchpad/EC) at 00:15.*.

## Storage

| Slot | Device | Driver |
| --- | --- | --- |
| 02:00.0 | Samsung PM9A1/980 PRO NVMe (PCIe 4.0) | `nvme` |
| 03:00.0 | Samsung S4LV008 NVMe | `nvme` |

Both controllers expose standard NVMe capabilities; firmware supports disk encryption via BIOS.

## Networking

- **Wi-Fi**: Intel CNVi WiFi 6E (00:14.3) using `iwlwifi`.
- **Bluetooth**: Enabled via CNVi module (`hardware.bluetooth.enable = true` in NixOS profile).
- No onboard wired NIC; use USB/TB adapters if required.

## Audio

- Intel Raptor Lake-P/U/H cAVS (00:1f.3) driven by `snd_hda_intel`, `snd_soc_avs`, `snd_sof_pci_intel_tgl`.
- PipeWire stack recommended (configured in `modules/features/desktop/plasma/nixos.nix`).

## Sensors / Power

- Thermal management handled by Intel DPTF participants (00:04.0) + `proc_thermal_pci`.
- `thermald`, `power-profiles-daemon`, `bolt`, and `fwupd` should stay enabled (see `modules/features/hardware/tuxedo/infinitybook-pro-16-gen8/nixos.nix`).
- `programs.light` is enabled for backlight control; consider adding udev rules for brightness keys if needed.

## Notes for NixOS Configuration

- Use PRIME offload (`hardware.nvidia.prime`) with bus IDs `Intel: PCI:0:2:0`, `NVIDIA: PCI:1:0:0`.
- Blacklist `nouveau` (`boot.blacklistedKernelModules = [ "nouveau" ]`).
- Keep firmware packages enabled (`hardware.enableAllFirmware = true`).
- Thunderbolt access rule in `services.udev.extraRules` grants `0660` permissions for logged-in users.
- Install diagnostic tools (`nvtopPackages.full`, `powertop`) for GPU and power monitoring.
- Sessions default to the NVIDIA renderer for peak performance; set `desktop.gaming.defaultRenderer = "intel"` if you prefer the iGPU to handle compositing and only offload specific apps.
- Enable `powerManagement.powertop.enable = true` to reapply powertop tunables on boot/resume and set `networking.networkmanager.wifi.powersave = true` to reduce idle draw from the Intel CNVi radio.

## Battery / Power Diagnostics

Run the helper script whenever you need to profile battery drain on Tux:

```bash
cd /home/lukasf/git/lukasfriedhoff/nix
sudo ./scripts/collect-power-metrics.sh
```

The script captures:

- `powertop` CSV/HTML snapshots (per-device residency + tunables).
- CPU package draw via `turbostat`.
- Intel and NVIDIA GPU activity logs (`intel_gpu_top`, `nvidia-smi dmon/pmon`).
- Top CPU / memory processes and active I/O offenders (`ps`, `iotop`).
- Battery discharge data from both `upower` and `/sys/class/power_supply`.

Inspect the generated directory printed at runtime (e.g. `/tmp/power-metrics-YYYYMMDD-HHMMSS`). Start with `powertop.html` for hardware metrics, `top-cpu.txt` / `top-mem.txt` for process-level issues, and `nvidia-processes.txt` for workloads stuck on the dGPU. Sharing this folder (or select files) will make it easy to pinpoint the culprits.

This document should be updated whenever hardware changes (e.g., storage swap, docking expansion) or when new kernel quirks are discovered.
