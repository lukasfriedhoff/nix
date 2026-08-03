# srv9 hardware inventory

Collected from the NixOS minimal ISO on 2026-08-02 before installation.

## Platform

- System: Dell EMC PowerEdge R740xd.
- CPU: two Intel Xeon Gold 6226R processors, 16 cores each, 64 threads total.
- Memory: 219 GiB detected by the ISO.
- Boot mode: UEFI.
- Storage controller: Dell PERC H730P / Broadcom MegaRAID SAS-3 3108.

## Network

- `eno1np0`: Intel X710 10 GbE SFP+, MAC `e4:43:4b:f2:1a:42`; management/native VLAN 30.
- `eno2np1`: second Intel X710 10 GbE SFP+ port, initially disconnected.
- `eno3` and `eno4`: Intel I350 1 GbE ports, initially disconnected.

The initial configuration uses only `eno1np0`. It carries untagged management
traffic and tagged VLANs 10, 12, 13, 20, 40, and 50. Initrd SSH unlock is pinned
to this interface to avoid probing disconnected links.

## Physical disks

| PERC slot | Model | Capacity | Media | Planned use |
|-----------|-------|----------|-------|-------------|
| 0 | Seagate ST8000NM0205 | 8 TB | HDD | Longhorn |
| 1 | Seagate ST8000NM0205 | 8 TB | HDD | Longhorn |
| 2 | Samsung MZILT800HBHQ0D3 | 800 GB | SAS SSD | Encrypted NixOS root |
| 3 | Samsung MZILT800HBHQ0D3 | 800 GB | SAS SSD | Longhorn |
| 4 | Samsung MZILT800HBHQ0D3 | 800 GB | SAS SSD | Longhorn |
| 5 | Samsung MZILT800HBHQ0D3 | 800 GB | SAS SSD | Longhorn |
| 6 | Seagate ST18000NM005J | 18 TB | HDD | Longhorn |
| 9 | Seagate ST18000NM005J | 18 TB | HDD | Longhorn |

All physical disks passed the available SMART health checks during the ISO
survey.

## Controller layout

The H730P is configured in HBA mode and exposes all eight drives directly to
Linux. The declarative layout uses:

- one encrypted NixOS system disk in SSD slot 2, without RAID;
- seven directly attached, individually encrypted Longhorn filesystems in slots
  0, 1, 3, 4, 5, 6, and 9.

Longhorn supplies replication for application data. No software RAID or PERC
virtual disks remain.

At discovery time the controller contained a degraded 8 TB RAID1 virtual disk
with VMware VMFS partitions. The old virtual disk and foreign metadata were
removed, the controller was switched to HBA mode, and all eight disks were
wiped before deployment.
