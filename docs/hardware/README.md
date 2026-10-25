# Hardware Documentation

This directory contains hardware-specific documentation for each managed device.

## Device Inventory

| Host | Device | Status |
|------|--------|--------|
| tux-h4xx-01 | TUXEDO InfinityBook Pro 16 Gen8 | [Documented](tux-h4xx-01.md) |
| tab-h4xx-02 | ASUS Vivobook T3300 | [Documented](tab-h4xx-02.md) |
| lenovo-h4xx-03 | Lenovo ThinkPad P15 Gen 2i | [Draft](lenovo-h4xx-03.md) |
| lenovo-h4xx-04 | Lenovo ThinkPad P15 Gen 2i | [Retired](lenovo-h4xx-04.md) (host removed from the flake) |
| srv1 | Supermicro server | See host config; disks in [cluster-disk-inventory.md](cluster-disk-inventory.md) |
| srv2 | Homelab server | See host config |
| srv8 | Homelab server | [Documented](srv8.md) |
| srv9 | Dell PowerEdge R740xd | [Documented](srv9.md) |
| srv4-vm-01 | Virtual machine | N/A |
| virtual-05 | Virtual desktop | N/A |

## Cluster storage

[`cluster-disk-inventory.md`](cluster-disk-inventory.md) records the physical
disk -> LUKS mapper -> Longhorn disk -> tag chain for srv1/srv8/srv9, plus the
constraints that follow from it: schedulable HDD exists on srv9 only (so the
2-replica `*-disk-*-2r` storage classes cannot be satisfied), every Longhorn
disk on srv8 is USB-attached and administratively disabled, the `nvme` tag means
"fast tier" rather than a bus, and no node has `smartctl` installed.

## Hardware Quirks

### TUXEDO InfinityBook Pro 16 Gen8 (tux-h4xx-01)

- **TUXEDO platform stack**: `hardware.tuxedo-drivers` + TUXEDO control center (`tccd`) enabled
- **NVIDIA PRIME**: Sync mode with NVIDIA renderer by default (host overrideable)
- **Wi-Fi defaults**: Keep TUXEDO-like NM settings (`wifi.powersave=3`, no scan MAC randomization)
- **Audio**: PipeWire tuned with higher quantum for stability on this host profile

See [`tux-h4xx-01.md`](tux-h4xx-01.md) for full hardware inventory.

Additional TUXEDO analysis:

- [`tuxedo-kernel-diff-report.md`](tuxedo-kernel-diff-report.md) (commit-level + module-level delta report)
- [`tuxedo-missing-modules-implementation-plan.md`](tuxedo-missing-modules-implementation-plan.md) (regression verification runbook)

### ASUS Vivobook T3300 (tab-h4xx-02)

- **SD card quirk**: Requires `sdhci.debug_quirks=0x20000` kernel parameter
- **Low RAM (4GB)**: Enable zram swap with 150% memory, disable GNOME tracker
- **eMMC storage**: Enable fstrim, reduce journald writes
- **Intel microcode**: Force update via `hardware.cpu.intel.updateMicrocode`

See [`tab-h4xx-02.md`](tab-h4xx-02.md) for full hardware inventory.

## Adding New Hardware

1. Run the hardware survey script:
   ```bash
   sudo ./scripts/hardware-survey.sh
   ```

2. Create a hardware module in `modules/features/hardware/<vendor>/<model>/nixos.nix`
3. Enable it in the host config:
   ```nix
   hardwareProfiles.<vendor>.<model>.enable = true;
   ```

4. Document the hardware in `docs/hardware/<hostname>.md`

5. Add any required kernel parameters or quirks to the host configuration

## Power Management

All laptop hosts include the laptop profile (`modules/features/desktop/laptop/nixos.nix`) which provides:

- auto-cpufreq for dynamic CPU frequency scaling
- thermald for Intel thermal management
- power-profiles-daemon for desktop environment integration
- WiFi power saving
- Periodic SSD TRIM
- Kernel tuning for reduced disk writes

Override specific settings in host configuration if needed.
