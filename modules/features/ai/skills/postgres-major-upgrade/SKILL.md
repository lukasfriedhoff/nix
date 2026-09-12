---
name: postgres-major-upgrade
description: CNPG PostgreSQL major version upgrades — offline (declarative pg_upgrade, short downtime) and online (logical replication live migration, no downtime)
globs:
  - "**/postgres.yaml"
  - "**/postgres*.yaml"
  - "**/scheduled-backup*.yaml"
---

# PostgreSQL Major Upgrades with CloudNativePG

Two paths, pick by downtime tolerance and DB size:

| | Offline (declarative) | Online (logical replication) |
|---|---|---|
| Downtime | Full outage during `pg_upgrade` (minutes for small DBs) | Near-zero (seconds at cutover) |
| Requires | CNPG operator >= 1.26 (homelab runs 1.30) | CNPG >= 1.25; tables need PK/replica identity |
| Effort | One-line GitOps change | New cluster + Publication/Subscription + cutover |
| Best for | Small/medium DBs, maintenance-window OK | Large DBs, zero-downtime, or cross-cluster moves |

Homelab conventions: clusters pin PG via `imageName:` in `flux-apps/apps/<app>/postgres.yaml`.
Fleet standard image: `ghcr.io/cloudnative-pg/postgresql:18.x-system-trixie`. Plugin: `nix run nixpkgs#kubectl-cnpg -- <cmd>`.

## Hard prerequisites (both paths)

1. **The PRIMARY must be healthy.** A replica stuck `replicating` with readiness 500 is usually a pg_rewind loop (old primary, diverged WAL gone). Fix options: `kubectl cnpg destroy <cluster> <n> -n <ns>` (deletes that instance's PVC, CNPG re-clones; destructive → user must run it) — **or, verified 2026-09-12: the offline major upgrade itself fixes it**, because it destroys and re-clones ALL replica PVCs from the upgraded primary. A cluster that is not-Ready *only because of wedged replicas* can go straight into Path A; only the primary's pgdata matters.
2. **Fresh backup**: `kubectl cnpg backup <cluster> -n <ns>` (or a Backup CR) and confirm `phase: completed`.
3. **Extensions**: verify every extension in the DB has a build for the target major in the CNPG image (system images bundle common ones; custom extensions need an image with both versions).
4. PG 17.0–17.5 source bug: `max_slot_wal_keep_size` must be `-1` or pg_upgrade fails.

## Path A — Offline declarative upgrade (short downtime)

CNPG runs `pg_upgrade --link` in-place when you raise the image major.

1. GitOps edit — bump only the major in `imageName`:
   ```yaml
   # flux-apps/apps/<app>/postgres.yaml
   spec:
     imageName: ghcr.io/cloudnative-pg/postgresql:18.4-system-trixie  # was :16.13-...
   ```
   Commit → push → flux reconcile (or `kubectl apply` in an emergency; keep GitOps in sync).
2. What CNPG does (expect FULL outage, all instances down):
   - shuts down all pods; records old version in `.status.pgDataImageInfo`
   - runs a Job named `<cluster>-major-upgrade` executing `pg_upgrade --link` into NEW pgdata dirs (source pgdata is left intact — that's the rollback guarantee)
   - **destroys replica PVCs** and re-clones replicas from the upgraded primary (re-clone time ∝ DB size)
3. Monitor:
   ```bash
   kubectl -n <ns> get jobs | grep major-upgrade
   kubectl -n <ns> logs job/<cluster>-major-upgrade -f
   kubectl -n <ns> get cluster <cluster> -w   # phase back to "Cluster in healthy state"
   ```
4. Rollback on failure: revert `imageName` to the old major → operator deletes the failed upgrade job and restarts on the original (unmodified) data dir.
5. Post-upgrade (do all three):
   - `kubectl cnpg psql <cluster> -n <ns> -- -c 'ANALYZE'` per database (pg_upgrade drops optimizer stats)
   - if the upgrade job emitted `update_extensions.sql`, run it as superuser
   - **new base backup immediately** — old-major WAL archive cannot restore the new major. Homelab pattern: bump the backup `generation` prefix var (e.g. `g20260801/`) in the overlay so the new-major backups land under a fresh prefix, mirroring the lldap/authelia scheme.
6. Follow-ups: bump any `postgres:<major>-alpine` *client* images (psql maintenance Jobs) to match, e.g. immich repair jobs.

## Path B — Online live migration (logical replication, no downtime)

New cluster on the target major subscribes to the old one; cutover is a brief write-freeze.

1. **Source cluster** needs a role with `login: true, replication: true` (add under `managed.roles`) — CNPG's default `wal_level=logical` already suffices.
2. **Destination cluster** on the NEW major, schema-only import from the source:
   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Cluster
   metadata: { name: <new>, namespace: <ns> }
   spec:
     instances: 3
     imageName: ghcr.io/cloudnative-pg/postgresql:18.4-system-trixie
     bootstrap:
       initdb:
         import:
           type: microservice        # one DB; use monolith for many
           schemaOnly: true          # structure only; data comes via replication
           databases: [app]
           source: { externalCluster: <old> }
     externalClusters:
       - name: <old>
         connectionParameters: { host: <old>-rw.<ns>.svc, user: app, dbname: app }
         password: { name: <old>-app, key: password }
   ```
3. **Publication** (source) + **Subscription** (destination):
   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Publication
   metadata: { name: <old>-pub, namespace: <ns> }
   spec:
     cluster: { name: <old> }
     dbname: app
     name: migration_pub
     target: { allTables: true }
     publicationReclaimPolicy: delete
   ---
   apiVersion: postgresql.cnpg.io/v1
   kind: Subscription
   metadata: { name: <old>-to-<new>, namespace: <ns> }
   spec:
     cluster: { name: <new> }
     dbname: app
     name: migration_sub
     externalClusterName: <old>      # must match an externalClusters entry on <new>
     publicationName: migration_pub
     subscriptionReclaimPolicy: delete
   ```
   Initial table data copies automatically on subscription start; then it streams.
4. **Monitor catch-up**: compare row counts (`kubectl cnpg psql <new> -- app -qAt -c 'SELECT count(*) FROM <t>'`) and `pg_stat_subscription` / `pg_stat_replication` lag on the source.
5. **Cutover** (the only impact window):
   1. Stop/quiesce application writes (scale app to 0 or maintenance mode).
   2. Wait for lag = 0.
   3. **Sync sequences** (NOT replicated!): `kubectl cnpg subscription sync-sequences <new> --subscription=migration_sub`
   4. Repoint the app to `<new>-rw` (Service name / app secret / `${...}_host` var in flux-cluster overlay).
   5. Verify, then delete Subscription + Publication (reclaim policy `delete` cleans PG objects); decommission the old cluster later.
6. **Not replicated — plan around**: DDL (freeze schema during migration), sequences (step 5.3), large objects; every replicated table needs a PK or replica identity.

## Field notes (immich 16.13 → 18.4, 2026-09-12)

- Timings for a ~360MB DB on Longhorn: `pg_upgrade --link` job ~1 min; each replica re-clone (join job) ~5–10 min on USB-backed nodes; total not-Ready window ~15–25 min, but the app-visible outage is only the pg_upgrade + primary restart (~2–3 min).
- Verify extension availability empirically, don't trust docs: `kubectl run ext-check --image=<target-image> --restart=Never --command -- sh -c 'ls /usr/share/postgresql/<major>/extension/ | grep <ext>'`. The `*-system-trixie` images ship pgvector + contrib.
- After upgrade also `ALTER EXTENSION vector UPDATE;` (pg_upgrade keeps the old extension version; the image ships a newer one).
- `kubectl get backup` is AMBIGUOUS (matches another CRD; with 2>/dev/null it looks like empty output) — always `kubectl get backups.postgresql.cnpg.io`.
- Flux kustomizations with `wait=true` + long timeout: a cluster that's been not-Ready blocks the NEXT revision's apply until the in-flight health wait times out — the imageName bump can take up to `timeout` (e.g. 15m) to land.
- Bump any `postgres:<major>-alpine` psql *client* images (maintenance Jobs) in the same change set.

## Verification checklist (either path)

- `kubectl -n <ns> get cluster <cluster>` → "Cluster in healthy state", all instances healthy
- app connects + reads/writes (check app logs, not just the DB)
- `SELECT version();` shows the new major
- ScheduledBackup fired successfully on the new major (check `LastBackupSucceeded`)
- Mimir alerts quiet (CNPGWALArchiveStalled etc.)
