# srv8 hardware inventory

Collected from the NixOS minimal ISO on 2026-06-05 before installation.

## Platform
- CPU: AMD Ryzen 5 5625U with Radeon Graphics, 6 cores / 12 threads.
- Memory: 15 GiB detected by the ISO.
- GPU: AMD Barcelo integrated graphics.
- Virtualization: AMD-V supported.

## Network
- `enp4s0`: Intel I226-V, MAC `1c:83:41:33:1b:37`, connected to MikroTik `ether3`, management/native VLAN 30.
- `eno1`: Realtek RTL8111/8168/8211/8411, MAC `1c:83:41:33:1b:38`, connected to MikroTik `ether4` but had no carrier during the ISO scan.
- `wlp3s0`: Realtek RTL8821CE Wi-Fi, not used for server networking.

Post-install networking uses `bond0` in active-backup mode over `enp4s0` and `eno1`. Initrd remote unlock intentionally uses the first physical link instead of LACP to keep DHCP and SSH unlock simple and reliable.

## Disks
- Root: `nvme-FORESEE_512GB_SSD_MCT5342001673`, 476.9 GiB NVMe, wiped by disko and used for encrypted NixOS root.
- Longhorn SSD: `ata-T-FORCE_1TB_TPBF2209020040602781`, 953.9 GiB, moved from srv2.
- Longhorn HDD: `ata-WDC_WD40EFRX-68N32N0_WD-WCC7K2FFFP9P`, 3.6 TiB, moved from srv2.
- Longhorn USB HDD: `usb-Seagate_BUP_Slim_BK_NA7WEQ6F-0:0`, 1.8 TiB USB SATA disk.
- Installer USB: `usb-SanDisk_Extreme_AA011109121938303132-0:0`, 59.6 GiB, excluded from disko.

All non-root data disks are declared as Longhorn disks in `resources/homelab/disks.nix` and encrypted with the shared srv8 Longhorn LUKS secret.

## Scan gaps
- The ISO did not include `sensors` or `dmidecode`, so thermal sensor and firmware tables were not captured.
- SMART data was captured where the USB/SATA bridge exposed it.
