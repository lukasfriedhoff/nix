---
name: longhorn
description: Longhorn distributed block storage — official 1.12 best practices plus homelab field lessons (rebuilds, engine upgrades, RWX share-manager, USB-disk realities)
---

# Longhorn Skill

Operational guidance for Longhorn (v1.12.x), from the official best practices plus hard-won homelab incident experience. Sources: https://longhorn.io/docs/1.12.1/best-practices/

## Sizing & environment (official)

- Minimum: 3 nodes, 4 vCPU + 4 GiB RAM each. **Latency matters more than IOPS/throughput for volume stability** — SSD/NVMe for production; HDD only with that caveat.
- Network: 10 Gbps between nodes recommended; a dedicated storage network improves stability.
- Kernel >= 5.8 (5.17+ for freeze-fs snapshots). CoreDNS >= 2 replicas.
- Dedicate a disk to Longhorn (not the root disk). Root disk fallback: min-available 25% + overprovisioning 100%; dedicated disk: min-available 10%. Extra disks belong in `/etc/fstab`; use `mount --bind`, not symlinks. LVM-aggregate multiple disks for future growth.
- Guaranteed Instance Manager CPU: 12% default — starving instance-managers destabilizes engines exactly when the node is busiest.
- Don't modify the default `longhorn` StorageClass; create new SCs for different parameters.
- One data engine (V1 or V2) per cluster; V2 wants local NVMe + hugepages + kernel 6.7+.

## Key settings (exact names)

| Setting | Production guidance |
|---|---|
| `default replica count` | 2 (availability vs disk efficiency); 3 for critical |
| `replica-soft-anti-affinity` (node level) | `false` — never co-locate replicas |
| `allow-volume-creation-with-degraded-availability` | `false` |
| `replica-auto-balance` | `least-effort` |
| `data locality` | `best-effort` default; `strict-local` for apps that replicate themselves (databases with own HA) |
| `concurrent-replica-rebuild-per-node-limit` | bound it (homelab: 2) — unbounded rebuilds crush slow disks |
| `concurrent-automatic-engine-upgrade-per-node-limit` | **0 = engine upgrades after a Longhorn upgrade NEVER complete** — set >= 1 (homelab: 3) |
| `replica-replenishment-wait-interval` | default 600s — volumes sit "degraded" this long after a restart before rebuilding; expected, not a fault |
| storage tags | tier disks (`nvme`/`ssd`/`disk`) and match SCs to tags |

## Volume & space maintenance (official)

- Recurring **backup** jobs to an object store (S3 preferred over NFS) for critical volumes + periodic system backups; without a backupstore, at least a recurring snapshot per volume.
- Periodically **trim filesystems** (`fstrim`) inside volumes and clean up system-generated snapshots — snapshot chains eat space invisibly.
- ext4 workloads: add a liveness check so the pod recovers after network-interruption remounts.

## Field lessons (homelab, earned the hard way)

- **Engine-image upgrades are half of every Longhorn upgrade.** After bumping Longhorn, volumes stay on the old engine image until each is upgraded; with the auto-upgrade limit at 0 they strand forever, old instance-managers half-drain, and **replica rebuilds on those volumes stall with empty `instanceManagerName`**. Check: `kubectl -n longhorn-system get volumes.longhorn.io -o json | jq '[.items[].spec.image] | group_by(.) | map({(.[0]): length})'` — one image should remain when healthy.
- **Rebuild stalls**: distinguish (a) waiting on `replica-replenishment-wait-interval` (normal, be patient), (b) stopped replicas on a dead IM (delete the stopped replica CR → forces re-place), (c) old-engine volumes (fix the engine image first). Active rebuilds show in `engines.longhorn.io` `.status.rebuildStatus` with progress %.
- **RWX = one NFS server pod** (`share-manager-<pvc>` in longhorn-system). All clients funnel through it: a metadata storm from ONE client (rsync tree-walk, find, du) degrades every other consumer of that volume — schedule bulk scans off-hours and keep `--bwlimit` on migrations. cgroup note: an **unthrottled writer to a slow volume OOMs on dirty page cache** — bwlimit is also a memory guard.
- **Online expansion needs a healthy engine**; if expansion wedges (frontend not growing), the fix path is detach/reattach — never delete the engine CR (wedges the volume in `state=creating`; recovery required a `--subresource=status` patch to `detached`). Don't combine expansion + scale-up + bulk copy on the same volume simultaneously.
- **USB-attached disks (~10ms latency) violate the latency-first rule**: expect slow rebuilds, degraded-state churn after every restart, and share-manager hiccups. Tag them `disk` and keep latency-sensitive volumes (databases) on real SAS/NVMe nodes. An SC named "nvme" is only as fast as the actual backing disk.
- **Share-manager restart = new service IP = stale node mounts.** When an RWX share-manager pod restarts, its Service can get a NEW ClusterIP; nodes with existing kernel NFS mounts to the OLD IP hang (`dmesg: nfs: server <old-ip> not responding`), and because RWX volumes stage once per node, kubelet's volume pipeline on that node wedges — new pods stick at `Init:0/N` with `context deadline exceeded` on the volume. Diagnose: compare `mount | grep <pvc-id>` IPs on the node vs the current SM service IP. Fix: `umount -f -l` the stale paths (root) or delete the pod(s) holding them; replacements mount the new IP.
- **open-iscsi version bumps invalidate `/etc/iscsi/nodes`** and kill Longhorn attachment on that node — pin/plan open-iscsi upgrades (see memory: longhorn-openiscsi-upgrade-trap).
- **Decommissioning a cluster leaves its backup bucket forever** — Longhorn has no S3-side retention; add "delete `<cluster>-longhorn-backups`" to the teardown checklist.
- Robustness counters fluctuate during maintenance (restarts re-trigger the 600s replenishment wait). Judge convergence by **zero `failedAt` replicas + rebuilds progressing**, not by the instantaneous degraded count.

## Quick diagnostics

```bash
# fleet robustness + engine-image spread
kubectl -n longhorn-system get volumes.longhorn.io -o json | python3 -c "
import json,sys;from collections import Counter
d=json.load(sys.stdin)
print(Counter(v['status'].get('robustness') for v in d['items']))
print(Counter(v['spec']['image'].split(':')[-1] for v in d['items']))"

# active rebuilds with progress
kubectl -n longhorn-system get engines.longhorn.io -o json | python3 -c "
import json,sys
for e in json.load(sys.stdin)['items']:
    for r,i in (e['status'].get('rebuildStatus') or {}).items():
        if i.get('isRebuilding'): print(e['metadata']['name'], i.get('progress'),'%')"

# settings that gate recovery
kubectl -n longhorn-system get settings.longhorn.io \
  concurrent-replica-rebuild-per-node-limit \
  concurrent-automatic-engine-upgrade-per-node-limit \
  replica-replenishment-wait-interval -o custom-columns=NAME:.metadata.name,VALUE:.value
```
