# Hardware Documentation

This directory contains hardware-specific documentation for each managed device.

## Device Inventory

| Host | Device | Status |
|------|--------|--------|
| tux-h4xx-01 | TUXEDO InfinityBook Pro 16 Gen8 | [Documented](tux-h4xx-01.md) |
| tab-h4xx-02 | ASUS Vivobook T3300 | [Documented](tab-h4xx-02.md) |
| srv1 | Supermicro server | See host config |
| srv4-vm-01 | Virtual machine | N/A |

## Hardware Quirks

### TUXEDO InfinityBook Pro 16 Gen8 (tux-h4xx-01)

- **ACPI GPE storm**: Requires `acpi_mask_gpe=0x6F` kernel parameter
- **NVIDIA Prime**: Use offload mode with Intel iGPU as primary
- **Thunderbolt**: Needs udev rules for user access
- **Audio**: Use PipeWire with higher quantum for stability

See [`tux-h4xx-01.md`](tux-h4xx-01.md) for full hardware inventory.

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

2. Create a hardware module in `modules/nixos/hardware/<vendor>/<model>.nix`

3. Document the hardware in `docs/hardware/<hostname>.md`

4. Add any required kernel parameters or quirks to the host configuration

## Power Management

All laptop hosts include the laptop profile (`modules/nixos/profiles/desktop/laptop.nix`) which provides:

- auto-cpufreq for dynamic CPU frequency scaling
- thermald for Intel thermal management
- power-profiles-daemon for desktop environment integration
- WiFi power saving
- Periodic SSD TRIM
- Kernel tuning for reduced disk writes

Override specific settings in host configuration if needed.
