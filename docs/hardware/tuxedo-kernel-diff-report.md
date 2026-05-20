# TUXEDO Kernel Diff Report (tux-h4xx-01)

Date: 2026-05-18  
Last verified: 2026-05-20  
Host: `tux-h4xx-01`  
Model: `TUXEDO InfinityBook Pro Gen8 (MK2)`  
Board vendor: `NB02` (`/sys/devices/virtual/dmi/id/board_vendor`)

## Scope

This report answers:

1. What is different between the TUXEDO kernel branch and current Nix kernel stack?
2. Which TUXEDO kernel modules are present on TUXEDO OS?
3. Which of those are relevant for this specific notebook (`NB02`)?
4. What is the current active Nix runtime status?

## Sources Used

- TUXEDO kernel repo:
  - `https://gitlab.com/tuxedocomputers/development/packages/linux`
  - local clone: `/tmp/linux-tuxedo-full`
  - branch: `tuxedo-6.17-24.04`
- Mounted TUXEDO OS root:
  - `/run/media/lukasf/14a96c3c-0cc5-4877-a43e-f9742a6fd5e6`
- Active Nix runtime:
  - `uname -r` -> `6.18.31`
  - loaded modules via `lsmod`
  - available modules via `modinfo`

## Commit-Level Diff (TUXEDO Branch)

Ubuntu HWE anchor commit:

- `0694e810b1bd` `UBUNTU: Ubuntu-hwe-6.17-6.17.0-29.29~24.04.1`

Compared range:

- `0694e810b1bd..cfc0272084e6` (current branch tip)

Counts in range:

- Total commits: `98`
- `TUXEDO:` commits: `39`
- `TUXEDO: Ubuntu-tuxedo-*` release-marker commits: `35`
- TUXEDO infra/packaging commits: `4`
- Remaining upstream commits: `59`

TUXEDO infra/packaging commits in this range:

- `83a0571c40d8` `TUXEDO: Add automatic update scripts`
- `72974914fdc4` `TUXEDO: Create abstracted debian directory`
- `b901e68a7d10` `TUXEDO: Initialize abstracted debian directory`
- `a70b5857cde2` `TUXEDO: Disable update scripts debug output`

Notebook-relevant upstream commits present in this range:

- i915 backlight/VESA handling series (9 commits)
- i915 DP/VBT eDP joiner fixes (2 commits)
- ALSA HDA quirks (2 commits)

Notable detail:

- The latest tip commit (`cfc0272084e6`) only changes `debian.tuxedo-6.17/changelog` vs its parent (release metadata bump).

## TUXEDO OS Module Inventory (Observed)

Detected in `.../lib/modules/6.17.0-118023-tuxedo/updates/dkms` and `kernel/drivers/platform/x86/tuxedo`:

```text
clevo_acpi
clevo_wmi
gxtp7380
ite_8291
ite_8291_lb
ite_8297
ite_829x
nvidia
nvidia-drm
nvidia-modeset
nvidia-peermem
nvidia-uvm
stk8321
tuxedo_compatibility_check
tuxedo_io
tuxedo_keyboard
tuxedo_nb02_nvidia_power_ctrl
tuxedo_nb04_kbd_backlight
tuxedo_nb04_keyboard
tuxedo_nb04_power_profiles
tuxedo_nb04_sensors
tuxedo_nb04_wmi_ab
tuxedo_nb04_wmi_bs
tuxedo_nb05_ec
tuxedo_nb05_fan_control
tuxedo_nb05_kbd_backlight
tuxedo_nb05_keyboard
tuxedo_nb05_power_profiles
tuxedo_nb05_sensors
tuxedo_tuxi_fan_control
tuxi_acpi
uniwill_wmi
```

## NB02 Relevance Mapping

Hardware signals on this host:

- DMI board vendor: `NB02`
- ACPI HID present: `UNIW0001`
- WMI GUIDs present:
  - `ABBC0F6B-*`
  - `ABBC0F6D-*`
  - `ABBC0F6F-*`
  - `ABBC0F72-*`
- WMI GUIDs absent:
  - `1F174999-3A4E-4311-900D-7BE7166D5055` (NB04 WMI BS)
  - `80C9BAA6-AC48-4538-9234-9F81A55E7C85` (NB04 WMI AB)

### Likely relevant for this notebook

- `tuxedo_keyboard` (core)
- `tuxedo_compatibility_check` (core dependency)
- `tuxedo_io` (core hardware I/O for TUXEDO stack)
- `tuxedo_nb02_nvidia_power_ctrl` (explicitly for board vendor NB02)
- `uniwill_wmi` (UNIW ACPI + matching WMI GUIDs present)
- `clevo_wmi` (matching WMI GUIDs present)

### Likely not relevant for this notebook

- `tuxedo_nb04_*` (NB04 GUIDs absent)
- `tuxedo_nb05_*` (NB05-specific family)
- `tuxi_acpi`, `tuxedo_tuxi_fan_control` (TUXI family)
- `clevo_acpi` (`CLV0001` not present)
- `ite_*`, `gxtp7380`, `stk8321` (platform/sensor dependent; not currently indicated by this host IDs)

## Current Runtime Status (2026-05-20)

Module presence check against active Nix runtime (`modinfo` + `lsmod`):

| Module | Present in current runtime | Loaded now | Notes |
| --- | --- | --- | --- |
| `tuxedo_keyboard` | yes | yes | Active |
| `tuxedo_compatibility_check` | yes | yes | Active |
| `tuxedo_io` | yes | yes | Active |
| `tuxedo_nb02_nvidia_power_ctrl` | yes | yes | Active |
| `uniwill_wmi` | yes | yes | Active |
| `clevo_wmi` | yes | yes | Active |
| `nvidia` | yes | yes | Present |
| `nvidia-drm` | yes | yes | Present |
| `nvidia-modeset` | yes | yes | Present |
| `nvidia-uvm` | yes | yes | Present |

Additional runtime parity checks (2026-05-20):

- NetworkManager defaults match TUXEDO OS behavior:
  - `wifi.powersave=3`
  - `wifi.scan-rand-mac-address=false`
- Sysctl defaults match TUXEDO OS:
  - `vm.swappiness=10`
  - `vm.max_map_count=1048576`
- TUXEDO service stack status:
  - `tccd.service`: active
  - `nvidia-powerd.service`: active
  - `tccd-sleep.service`: installed (inactive unless suspend/resume cycle)

## Practical Conclusion

The previously missing TUXEDO module issue is resolved.  
Remaining differences vs TUXEDO OS are:

1. Kernel source/patch provenance (TUXEDO 6.17 branch vs nixpkgs 6.18 mainline).
2. Boot cmdline is not a strict TUXEDO clone (`loglevel=3` and `loglevel=4` are both present currently).
3. TUXEDO OS ships additional Ubuntu/TUXEDO packaging hooks and suspend integration details that are not mirrored 1:1.
