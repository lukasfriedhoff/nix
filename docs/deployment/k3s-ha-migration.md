> **Status: COMPLETED 2026-08-25.** All three nodes run as control-plane/etcd
> members (verified: 3 API endpoints, 3 etcd members, srv2 migrated off sqlite).
> Kept as reference for how it was done and for the rollback notes.
> Note: step 3 happened automatically — CI fast-forwards `deploy` from
> `develop` after checks pass; there is no manual promotion gate.

# k3s HA Migration: Single Control Plane → 3-Server Embedded etcd

## Why

On 2026-08-24 srv2 went hard-down. It was the **only** control plane (sqlite
datastore) and also hosted the only healthy cloudflared connectors plus the
k3s-bundled coredns. Result: every `*.h4xx.io` service returned 530 and
cluster DNS was dead, even though srv8/srv9 kept running all workloads.

This migration makes srv2, srv8 and srv9 all control planes with embedded
etcd, so losing any single node keeps the API, scheduling and DNS
rescheduling alive. The flux side (committed to `main` of flux-apps and
flux-cluster) adds cloudflared pod anti-affinity, traefik 2 replicas with
anti-affinity, and a coredns HPA/PDB so no single node carries all ingress
paths again.

## Order matters

A joining server can only join an **etcd-backed** cluster. srv2 must migrate
sqlite → etcd before srv8/srv9 flip from agent to server. comin deploys the
`deploy` branch on all three hosts on its own schedule, so the gate is the
merge into `deploy`, not per-host ordering. If srv8/srv9 happen to restart
k3s before srv2 has migrated, they crash-loop on join and recover on their
own once srv2's etcd is up — running workloads (containers) are not touched
by a k3s restart.

## Steps

1. **Power cycle srv2** (still on the old config). Wait until the cluster is
   fully healthy again: `kubectl get nodes` shows 3 Ready nodes, coredns and
   cloudflared pods running, `*.h4xx.io` reachable.
2. Flux will automatically reconcile the new `main` commits of flux-apps and
   flux-cluster (cloudflared/traefik/coredns HA). Verify:
   `flux get kustomizations -A` and
   `kubectl -n cloudflared get pods -o wide` → 2 pods on 2 different nodes.
3. **Promote nix `develop` → `deploy`** (fast-forward). comin applies it to
   all three hosts within its poll interval.
4. srv2 restarts k3s with `--cluster-init`: sqlite is migrated to embedded
   etcd in place. Expect a short API blip. Verify on srv2:
   `sudo k3s kubectl get --raw /healthz` and
   `sudo ls /var/lib/rancher/k3s/server/db/etcd` exists.
5. srv8 and srv9 restart k3s as servers and join. Verify:
   - `kubectl get nodes` → all three show `control-plane,etcd,master` roles
   - `sudo k3s kubectl get --raw /healthz?verbose` on each server
   - etcd members: `kubectl -n kube-system get lease -l ... ` or
     `sudo k3s etcd-snapshot ls` works on any server
6. **Quorum note**: 3 etcd members tolerate exactly one node down. Never run
   the cluster long-term with 2 members (worse than 1 — either loss kills
   quorum). If a node must be retired, remove it from etcd membership.

## Rollback

- srv8/srv9: revert `role = "server"` → `"agent"` (plus removing the
  `tlsSans` blocks), redeploy; delete the etcd member afterwards
  (`kubectl delete node` is not enough — use
  `sudo k3s etcd-snapshot` tooling / `etcdctl member remove`).
- srv2: etcd → sqlite has no automated path; restore from an etcd snapshot
  or the nightly host backup if the migration itself fails.

## Deliberately not included

- **keepalived API VIP** (`homelab.kubernetes.highAvailability`): the module
  currently asserts RKE2-only and every k3s node keeps a client-side
  load-balancer over all known servers once joined, so intra-cluster HA
  needs no VIP. A VIP would only stabilize external kubectl/flux bootstrap
  endpoints; revisit if `srv2.lab.h4xx.io` as the kubeconfig endpoint
  becomes a problem.
