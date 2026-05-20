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
- Backlight handling in TUXEDO OS relies on kernel backlight interfaces (`nvidia-wmi-ec-backlight` support) + `systemd-backlight`, not `acpilight`.

## TUXEDO OS Reference Baseline

Reference source: mounted TUXEDO OS root at
`/run/media/lukasf/14a96c3c-0cc5-4877-a43e-f9742a6fd5e6`.

- TUXEDO kernels installed:
  - `6.17.0-112020-tuxedo`
  - `6.17.0-113020-tuxedo`
  - `6.17.0-118023-tuxedo`
- TUXEDO kernel packaging reference checked:
  - `https://gitlab.com/tuxedocomputers/development/packages/linux` (`tuxedo-6.17-24.04`)
  - `debian.tuxedo-6.17/config/annotations` only overrides a small subset (e.g. `CONFIG_TUXEDO_NB04_WMI_AB=m`)
  - Most TUXEDO/NVIDIA platform modules are delivered via DKMS (`tuxedo-drivers`, `nvidia-dkms-580-open`) under `updates/dkms`
- TUXEDO/NVIDIA package set includes:
  - `tuxedo-control-center`, `tuxedo-drivers`, `tuxedo-fix-kvm-virt-at-load`
  - `tuxedo-fix-nvidia-preserve-vram-suspend`
  - `tuxedo-nvidia-default-open`, `tuxedo-nvidia-driver-580-open`
  - NVIDIA open driver packages (`nvidia-driver-580-open`, dkms stack)
- TUXEDO/NB modules present in kernel module tree:
  - `tuxedo_keyboard`, `tuxedo_io`, `tuxedo_compatibility_check`
  - `tuxedo_nb04_*` (keyboard/backlight/power_profiles/sensors/wmi_ab/wmi_bs)
  - `tuxedo_nb02_nvidia_power_ctrl`
- NVIDIA runtime modules present:
  - `nvidia`, `nvidia-modeset`, `nvidia-drm`, `nvidia-uvm`, `nvidia-peermem`
- Intel/Wi-Fi/audio modules present:
  - `i915`, `xe`, `iwlwifi`, `iwlmvm`, `btusb`, `snd_hda_intel`, SOF stack
- Relevant modprobe and NM config from TUXEDO OS:
  - `/etc/modprobe.d/nvidia-graphics-drivers-kms.conf`: `options nvidia-drm modeset=1`
  - `/etc/modprobe.d/common.conf`: blacklist `snd-mixer-oss`, `snd-pcm-oss`
  - `/etc/NetworkManager/NetworkManager.conf`: `wifi.scan-rand-mac-address=no`
  - `/etc/NetworkManager/conf.d/default-wifi-powersave-on.conf`: `wifi.powersave=3`
- Relevant kernel/sysctl defaults from TUXEDO OS:
  - `/etc/default/grub.d/02-tuxedo.cfg`: `loglevel=3 udev.log_level=3`
  - `/etc/sysctl.d/10-tuxedo-swappiness.conf`: `vm.swappiness=10`
  - `/etc/sysctl.d/55-tuxedo-vm-max_map.conf`: `vm.max_map_count=1048576`
- Enabled services observed:
  - `tccd.service`, `tccd-sleep.service`
  - `nvidia-powerd.service`, NVIDIA suspend/resume/hibernate hooks
  - `NetworkManager.service`, `power-profiles-daemon.service`, `bluetooth.service`

## NixOS Mapping Status

- Implemented in `hardwareProfiles.tuxedo.infinitybookPro16Gen8`:
  - `hardware.tuxedo-drivers.enable = true` (TUXEDO kernel module stack)
  - `services.power-profiles-daemon.enable = lib.mkDefault true`
  - `networking.networkmanager.wifi.scanRandMacAddress = lib.mkDefault false`
  - `networking.networkmanager.wifi.powersave = lib.mkDefault true`
  - `hardware.acpilight.enable = lib.mkForce false` (match TUXEDO OS approach)
  - `boot.kernelParams = [ "loglevel=3" "udev.log_level=3" ]`
  - `boot.kernel.sysctl.vm.swappiness = 10`
  - `boot.kernel.sysctl.vm.max_map_count = 1048576`
  - NVIDIA modesetting/power management/open module stack
  - PRIME bus IDs (`PCI:0:2:0` Intel, `PCI:1:0:0` NVIDIA)
  - `services.fwupd`, `services.thermald`, `services.hardware.bolt`
  - `boot.blacklistedKernelModules = [ "nouveau" "snd-mixer-oss" "snd-pcm-oss" ]`

## Current Runtime Verification (2026-05-20)

Live checks on `tux-h4xx-01` confirm:

- Booted and current generation are aligned (`/run/booted-system == /run/current-system`).
- TUXEDO platform modules are loaded:
  - `tuxedo_keyboard`
  - `tuxedo_compatibility_check`
  - `tuxedo_io`
  - `tuxedo_nb02_nvidia_power_ctrl`
  - `uniwill_wmi`
  - `clevo_wmi`
- NVIDIA stack is active:
  - `nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm`
- TUXEDO-related services:
  - `tccd.service`: active
  - `nvidia-powerd.service`: active
  - `tccd-sleep.service`: installed/enabled (inactive unless sleep hook runs)
- NetworkManager Wi-Fi defaults match TUXEDO OS baseline:
  - `wifi.powersave=3`
  - `wifi.scan-rand-mac-address=false`
- Sysctl parity is intact:
  - `vm.swappiness=10`
  - `vm.max_map_count=1048576`

Remaining deltas vs TUXEDO OS:

- Kernel branch differs (`6.18.x` nixpkgs kernel vs TUXEDO `6.17.x-tuxedo` branch).
- Boot cmdline includes extra args not strictly matching TUXEDO defaults (for example both `loglevel=3` and `loglevel=4` currently present).

## Notes for NixOS Configuration

- Use PRIME offload (`hardware.nvidia.prime`) with bus IDs `Intel: PCI:0:2:0`, `NVIDIA: PCI:1:0:0`.
- Blacklist `nouveau` plus legacy OSS ALSA compatibility modules (`snd-mixer-oss`, `snd-pcm-oss`).
- Keep firmware packages enabled (`hardware.enableAllFirmware = true`).
- Keep the TUXEDO kernel module stack enabled via `hardware.tuxedo-drivers`.
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
