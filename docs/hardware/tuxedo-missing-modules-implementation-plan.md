# Verification Runbook: TUXEDO Module Parity on tux-h4xx-01

Date: 2026-05-20  
Target host: `tux-h4xx-01`  
Related report: `docs/hardware/tuxedo-kernel-diff-report.md`

## Status

The previously missing TUXEDO NB02 module stack is now active on the booted system.

Loaded now:

- `tuxedo_keyboard`
- `tuxedo_compatibility_check`
- `tuxedo_io`
- `tuxedo_nb02_nvidia_power_ctrl`
- `uniwill_wmi`
- `clevo_wmi`

This document is kept as a regression verification runbook.

## Quick Verification

Run on `tux-h4xx-01`:

```bash
readlink -f /run/booted-system
readlink -f /run/current-system

lsmod | rg -i 'tuxedo|uniwill|clevo|nvidia'

modinfo tuxedo_keyboard
modinfo tuxedo_io
modinfo tuxedo_nb02_nvidia_power_ctrl
modinfo uniwill_wmi
modinfo clevo_wmi
```

Expected:

- `booted-system` and `current-system` are identical after reboot.
- All listed `modinfo` calls succeed.
- `lsmod` shows the NB02 stack loaded.

## Service Parity Checks

```bash
systemctl is-active tccd.service tccd-sleep.service nvidia-powerd.service
systemctl list-unit-files | rg -i '^tccd|nvidia-(powerd|suspend|resume|hibernate)'
```

Expected:

- `tccd.service` and `nvidia-powerd.service` are active.
- `tccd-sleep.service` exists (may be inactive outside suspend/resume transitions).

## Wi-Fi and Sysctl Parity Checks

```bash
rg -n "wifi\\.powersave|wifi\\.scan-rand-mac-address" \
  /etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/conf.d -S

sysctl -n vm.swappiness
sysctl -n vm.max_map_count
```

Expected:

- `wifi.powersave=3`
- `wifi.scan-rand-mac-address=false`
- `vm.swappiness=10`
- `vm.max_map_count=1048576`

## Remaining Differences vs TUXEDO OS

These are expected and currently accepted:

1. Kernel provenance differs (`nixpkgs 6.18.x` vs `6.17.x-tuxedo` branch).
2. Boot cmdline is not a strict byte-for-byte clone of TUXEDO OS.
3. Additional Ubuntu/TUXEDO packaging glue from TUXEDO OS is not mirrored 1:1.

## If Regression Appears

If modules disappear again after a rebuild:

```bash
nix eval --json .#nixosConfigurations.tux-h4xx-01.config.hardware.tuxedo-drivers.enable
nix eval --json .#nixosConfigurations.tux-h4xx-01.config.boot.extraModulePackages
nix eval --json .#nixosConfigurations.tux-h4xx-01.config.boot.kernelModules
```

Then rebuild and reboot:

```bash
sudo nixos-rebuild switch --flake /home/lukasf/git/lukasfriedhoff/nix#tux-h4xx-01
sudo reboot
```
