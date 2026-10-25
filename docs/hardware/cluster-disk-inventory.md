# Homelab k3s cluster: disk inventory and storage constraints

Surveyed 2026-10-25 on the live cluster (srv1, srv8, srv9 — post-Hiesfelden
relocation, nodes on `10.3.30.x`). Per-host platform details stay in
[`srv8.md`](srv8.md) and [`srv9.md`](srv9.md); this file records the
**physical disk → LUKS mapper → Longhorn disk → tag** chain and the
constraints that follow from it, because those constraints are what actually
cause incidents and they are not visible from any single host's config.

Re-survey with:

```bash
ssh <host> 'lsblk -d -o NAME,SIZE,ROTA,TRAN,MODEL,SERIAL'
ssh <host> 'lsblk -n -o NAME,MOUNTPOINT /dev/<disk>'
kubectl -n longhorn-system get nodes.longhorn.io -o json | jq -r '
  .items[] | .metadata.name as $n | .spec.disks | to_entries[]
  | "\($n) \(.key) \(.value.path) tags=\(.value.tags|join(",")) sched=\(.value.allowScheduling)"'
```

## srv1 — all SATA SSD

Root on a dedicated SSD; the other five are Longhorn.

| Phys | Size | Model | Bus | Mount | Longhorn disk | Tags | Sched | Used |
|---|---|---|---|---|---|---|---|---|
| sdf | 894G | SanDisk Ultra II 960GB | SATA | `/boot`, `/` | — (root) | — | — | 12% |
| sdc | 954G | T-FORCE 1TB | SATA | `longhorn-disk1` | `longhorn-ssd-1tb-a` | nvme,ssd | yes | 45% |
| sde | 954G | T-FORCE 1TB | SATA | `longhorn-disk2` | `longhorn-ssd-1tb-b` | nvme,ssd | yes | 55% |
| sdd | 954G | T-FORCE 1TB | SATA | `longhorn-disk3` | `longhorn-ssd-1tb-c` | nvme,ssd | yes | 28% |
| sda | 954G | T-FORCE 1TB | SATA | `longhorn-disk4` | `longhorn-ssd-1tb-d` | nvme,ssd | yes | 37% |
| sdb | 954G | T-FORCE 1TB | SATA | `longhorn-disk5` | `longhorn-ssd-1tb-e` | nvme,ssd | yes | 24% |

**srv1 has no HDD and no `disk`-tagged storage at all.** See the constraint below.

## srv8 — every Longhorn disk is USB

The only internal drive is the NVMe root. All three Longhorn disks hang off USB,
including the ones whose names suggest otherwise: `longhorn-disk-4tb` is a WD Red
in a USB enclosure, and `longhorn-ssd-1tb` is a T-FORCE SSD over USB.

| Phys | Size | Model | Bus | Mount | Longhorn disk | Tags | Sched | Used |
|---|---|---|---|---|---|---|---|---|
| nvme0n1 | 477G | (internal NVMe) | NVMe | `/boot`, `/`, swap | — (root) | — | — | 67% |
| sdb | 954G | T-FORCE 1TB | **USB** | `longhorn-disk1` | `longhorn-ssd-1tb` | nvme,ssd | **no** | 4% |
| sdc | 3.6T | WDC WD40EFRX-68N32N0 | **USB** | `longhorn-disk2` | `longhorn-disk-4tb` | disk | **no** | 1% |
| sda | 1.8T | Seagate BUP Slim BK | **USB** | `longhorn-disk3` | `longhorn-disk-2tb-usb` | disk | **no** | 1% |

All three are `allowScheduling: false` — an administrative flag, not a fault.
Longhorn reports them `Ready=True`/`Schedulable=True` with full capacity free.
They were disabled after the September 2026 rebuild storm, where USB-attached
replicas left 67 volumes degraded for 22 hours. **Re-enabling them brings that
risk back; do it deliberately, not as a quick fix for a degraded volume.**

Note srv8's root filesystem is at 67% on a 98G partition — the tightest root in
the cluster, worth watching.

## srv9 — the bulk storage node

| Phys | Size | Model | Media | Mount | Longhorn disk | Tags | Sched | Used |
|---|---|---|---|---|---|---|---|---|
| sdc | 745G | Samsung MZILT800HBHQ0D3 | SAS SSD | `/boot`, `/` | — (root) | — | — | 23% |
| sda | 7.3T | Seagate ST8000NM0205 | HDD | `longhorn-disk1` | `longhorn-disk-8tb-a` | disk | yes | 2% |
| sdb | 7.3T | Seagate ST8000NM0205 | HDD | `longhorn-disk2` | `longhorn-disk-8tb-b` | disk | yes | 27% |
| sdh | 16.4T | Seagate ST18000NM005J | HDD | `longhorn-disk3` | `longhorn-disk-18tb-a` | arr-media-v2,disk | yes | 28% |
| sdg | 16.4T | Seagate ST18000NM005J | HDD | `longhorn-disk4` | `longhorn-disk-18tb-b` | arr-media-v2,disk | yes | 30% |
| sde | 745G | Samsung MZILT800HBHQ0D3 | SAS SSD | `longhorn-disk5` | `longhorn-ssd-800gb-a` | nvme,ssd | yes | 41% |
| sdf | 745G | Samsung MZILT800HBHQ0D3 | SAS SSD | `longhorn-disk6` | `longhorn-ssd-800gb-b` | nvme,ssd | yes | 28% |
| sdd | 745G | Samsung MZILT800HBHQ0D3 | SAS SSD | `longhorn-disk7` | `longhorn-ssd-800gb-c` | nvme,ssd | yes | 36% |

All four 800 GB SAS SSDs are in use — three as Longhorn disks and `sdc` as the
encrypted root. There is no spare SSD here, contrary to what the count of three
`longhorn-ssd-800gb-*` disks against four physical SSDs suggests.

## Constraint: 2-replica HDD volumes cannot be satisfied

This is the one to remember.

`disk`-tagged (HDD) storage that is **schedulable** exists on **srv9 only** —
srv1 has no HDD, and srv8's are administratively disabled. But the 2-replica
storage classes demand two different nodes *and* two different disks:

```
longhorn-disk-rwo-2r / longhorn-disk-rwx-2r:
  diskSelector: disk
  numberOfReplicas: 2
  replicaSoftAntiAffinity: disabled        # strict -> two NODES required
  replicaDiskSoftAntiAffinity: disabled    # strict -> two DISKS required
```

With one eligible node the node requirement is unsatisfiable, and Longhorn
reports:

```
Scheduled=False  ReplicaSchedulingFailure
precheck new replica failed: disks are unavailable; tags not fulfilled
```

`nextcloud/nextcloud-data-hdd` (5 TiB) sat on a single replica from 2026-10-18
to 2026-10-25 for exactly this reason. **Enabling srv8 would not have fixed it
either** — srv8's largest disk has 3666 GiB free, less than the 5120 GiB the
volume needs. The workaround applied was per-volume:

```bash
kubectl -n longhorn-system patch volumes.longhorn.io <vol> --type merge \
  -p '{"spec":{"replicaSoftAntiAffinity":"enabled"}}'
```

That buys a second replica on a *different srv9 disk*, so the volume survives a
disk failure but not the loss of srv9. Disk anti-affinity is left strict so the
two replicas cannot land on the same spindle. **Real node-level redundancy for
bulk data needs HDD capacity on a second node** — that is a hardware decision,
not a settings change.

## Constraint: the `nvme` tag does not mean NVMe

`longhorn_nvme_disk_selector` defaults to `nvme`, so the `*-nvme-*` storage
classes select disks tagged `nvme`. In practice:

- srv1's five `nvme,ssd` disks are **SATA** SSDs.
- srv8's `longhorn-ssd-1tb`, also tagged `nvme,ssd`, is an SSD **over USB**.
- Only srv9's `longhorn-ssd-800gb-*` are genuinely enterprise SAS SSDs.

The tag means "fast tier", not a bus. Do not infer latency from it, and be aware
that re-enabling srv8 would put `nvme`-class workloads on USB.

## SMART monitoring (added 2026-10-25)

Until 2026-10-25 there was none at all — `smartctl` was not even installed on
the nodes, so nothing tracked reallocated sectors, flash wear or pending
failures on ~48 TB of HDD where several volumes are effectively single-replica.

Two halves now cover it:

- **Collection in-cluster**: a `smartctl-exporter` DaemonSet
  (`flux-apps/apps/monitoring/smartctl-exporter`) scraped into Mimir through the
  usual Alloy pod-annotation autodiscovery. It runs `privileged` because
  `smartctl --scan` reads `/dev`, so the host `/dev` must be mounted *at* `/dev`,
  and its SG_IO ioctls need the device opened writable — a read-only mount or a
  `SYS_RAWIO`/`SYS_ADMIN` capability set is not sufficient.
- **The CLI on the hosts**: `pkgs.smartmontools` is now in the `homelabDefaults`
  block of `hosts/common/default.nix`. It had only ever been installed for
  desktops. Every SMART alert's runbook step is "read `smartctl -a` on the node",
  which needs the binary present.

Dashboard: **SMART Disk Health** (`smart-disk-health`) in Grafana's *Storage*
folder. Alerts: `apps/monitoring/rules-sync/smart-alerts.yaml` — kept separate
from `alerts.yaml`/`rules.yaml`, which are generated from the kubernetes-mixin
and would overwrite anything added to them.

**srv8's USB disks answer SMART without any override.** smartctl auto-detects
them as `usbprolific`, and both the T-FORCE SSD and the WD40EFRX report
normally — no `-d sat` needed. The one exception is the 1.8 TB Seagate BUP Slim,
which does not appear at all.

**storage01 already had a smartctl exporter** (11 devices, `instance="storage01"`),
predating this work. The gap was the three k3s nodes, not the whole estate.

### Two traps that made whole nodes invisible

**1. Pin the exporter to v0.14.0. v0.15.0 returns HTTP 500 and zero metrics on
SAS.** It collects SCSI-only metrics
(`smartctl_scsi_percentage_used_endurance_indicator`,
`smartctl_verify_errors_corrected_by_*`,
`smartctl_verify_total_uncorrected_errors`) using descriptors it never
registers. The Prometheus client treats an unregistered descriptor as a
collection error and fails the **entire response**, not just the offending
series. srv9's four Samsung SAS SSDs trigger it, so srv9 — the node holding
~48 TB — reported nothing while srv1 and srv8 looked healthy and the dashboard
looked populated. **A single unsupported device blinds a whole node, and the
only symptom is in the response body.** Renovate must not bump this without
re-testing srv9.

**2. Exclude Longhorn's iSCSI devices or srv9 cannot be scraped at all.** Every
attached Longhorn volume appears as a `/dev/sdX` with model
`IET VIRTUAL-DISK`, and the exporter runs one `smartctl` per device serially.
srv9 discovered **94** devices and took **over 80 seconds** to answer
`/metrics`, against the chart's 10 s `scrapeTimeout`. The exclusion regex
(`^sd([g-z]|[a-z]{2,})$`) brings that to 14 devices and sub-second responses.
Note srv9's real disks are not `sd*` at all — they enumerate through the H730P
as `bus_0_megaraid_N` and `bus_0_sat+megaraid_N`.

### Findings from the first full collection (2026-10-25)

| Device | Finding |
|---|---|
| `storage01` `sdi` | **SMART assessment FAILED.** ST1000LM014-1EJ164-SSHD, serial W770473H, 901 power-on days. `End-to-End_Error` value 81 against threshold 97 (attribute 184 — corruption between drive cache and host). smartctl exit 88 = bits 3+4+6: disk failing, pre-fail attribute below threshold, errors in log. **Reallocated and pending sectors are both zero**, so looking only at sector counts would have missed it entirely. This is on the only backup target. |
| `srv1` `sdf` | 3 reallocated sectors. SanDisk Ultra II 960GB — srv1's **root** disk. Small and currently stable; watch the slope, not the value. |
| `storage01` | 6 devices return non-zero smartctl exit, i.e. no health data. Pre-existing. |

**Caveat on the alerts**: Mimir's Alertmanager has no receiver configured, so
these rules evaluate and show in Grafana but notify nobody. Wiring a receiver is
tracked separately in the second brain backlog.

## Related

- [`srv9.md`](srv9.md), [`srv8.md`](srv8.md) — platform, controller and network detail
- [`docs/services/backup.md`](../services/backup.md) — backup targets
- Second brain → `70 Entities/Systems/Homelab k3s Clusters` and the Longhorn runbooks
