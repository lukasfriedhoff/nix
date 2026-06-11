# Cluster Release and Cleanup Plan

## Goal

Make the Flux-managed Kubernetes clusters releasable without mixing experimental testing work into staging or production.

This plan intentionally keeps the `nix` repository on `develop` for now. Splitting Nix host configuration across testing, staging, and production branches would add abstraction and deployment complexity that is not needed for the immediate cleanup.

## Branch Model

Apply this model only to Flux-related repositories:

- `testing`: active testing cluster work and experiments.
- `develop`: staging cluster desired state.
- `main`: production desired state.
- Tags on `main`: immutable production release points and rollback anchors.

Initial target repositories:

- `flux-cluster`
- `flux-apps`
- `logDay` only if the deployed app/version is promoted through Flux references
- Any other Flux source repository referenced by `GitRepository` objects

Non-target repository:

- `nix` stays on `develop` for now.

## Desired Promotion Flow

1. Land experimental changes on `testing`.
2. Reconcile and validate `homelab-testing`.
3. Promote the same logical change to `develop`.
4. Reconcile and validate `homelab-staging`.
5. Promote to `main`.
6. Tag the production release after `homelab-prod` converges.

Promotion should be Git-based, not manual cluster mutation. Emergency fixes may go directly to the currently broken environment, but the same fix must be backported/forward-ported so branch state remains explainable.

## Current Cluster Roles

### Testing

Purpose:

- Fast iteration.
- Storage experiments.
- App integration experiments.
- Migration dry-runs.

Immediate focus:

- Make `homelab-testing` the first clean baseline.
- Keep experimental Longhorn RWX, media stack, Immich/Nextcloud linking, Matrix migration work here until stable.
- Remove stale failed jobs only after confirming current CronJobs and workloads are healthy.

### Staging

Purpose:

- Production-like validation gate.
- No long-running experiments.
- Same app topology as production where practical.

Immediate focus:

- Restore API access to `homelab-staging`.
- Point staging Flux sources at `develop`.
- Reconcile from a clean `develop` baseline.
- Keep staging storage smaller than prod, but structurally equivalent.

### Production

Purpose:

- Stable service environment.
- Only promoted and validated state.

Immediate focus:

- Fix missing production backup credentials and invalid backup endpoint config.
- Fix or explicitly disable prod-only resources that currently render invalid manifests.
- Recover or recreate faulted Longhorn volumes only after backup state is clear.
- Point production Flux sources at `main` or a pinned tag once branch split is ready.

## Backup Key and Secret Work

Production likely needs dedicated S3 backup credentials for:

- Longhorn backup target.
- CNPG backups for Nextcloud.
- CNPG backups for Immich.
- CNPG backups for Immich Photos.
- CNPG backups for Matrix.
- CNPG backups for Logday.
- Attic database backups if Attic is deployed in production.
- Monitoring object storage credentials if production monitoring writes to in-cluster S3.

Required cleanup:

- Create production S3 users/access keys per backup domain where possible.
- Store keys through SOPS in the production overlay.
- Add production secrets to the production overlay `kustomization.yaml`.
- Avoid inheriting empty backup defaults into production manifests.
- Make missing backup credentials fail early in testing/staging before promotion.

Open decision:

- Whether production backups should target the internal `object-storage/s3` service, an external S3 endpoint, or both.

## Storage Class Strategy

Use generic logical storage settings in app manifests and map them to concrete storage classes per overlay.

Generic config keys should express intent:

- `default_storage_class_name`
- `default_sts_storage_class_name`
- `database_storage_class_name`
- `cache_storage_class_name`
- `media_storage_class_name`
- `downloads_storage_class_name`
- `shared_rw_storage_class_name`
- App-specific overrides only where the generic class is not precise enough.

Concrete overlay mappings should express implementation:

- Testing maps generic classes to `testing-longhorn-*`.
- Staging maps generic classes to staging Longhorn classes.
- Production maps generic classes to production Longhorn classes.

Preferred class usage:

- Databases: RWO, SSD/NVMe-backed, usually 1 replica in single-node testing, higher only when the cluster can actually place replicas on separate disks/nodes.
- Caches: RWO, SSD-backed, small, disposable when the app tolerates it.
- Media libraries: RWX only when multiple pods need simultaneous access.
- Downloads: RWX for media stack coordination, large size, lower backup priority.
- Monitoring object data: RWO for single-replica S3 or object-store backend; do not use fault-prone replicated settings until Longhorn is healthy.
- Shared photo bridge: RWX only if Nextcloud and Immich both need live access.

Avoid:

- App manifests directly hardcoding environment-specific storage class names.
- Production inheriting empty NFS server, empty backup endpoint, or empty credential names.
- Using multi-replica Longhorn classes before there are enough healthy disks/nodes to place replicas safely.

## Testing-First Cleanup Plan

### Phase 1: Branch Preparation

- Create `testing` branches in Flux repositories from current `develop`.
- Update `homelab-testing` Flux `GitRepository` refs to `testing`.
- Keep `homelab-staging` on `develop`.
- Keep `homelab-prod` on current behavior until `main` promotion is ready.

Validation:

- Flux sources in testing report the `testing` branch revision.
- Flux Kustomizations in testing are Ready.

### Phase 2: Testing Baseline

- Remove stale failed one-shot pods/jobs after verifying their owning CronJobs are healthy.
- Verify Longhorn volumes are healthy.
- Verify every PVC is Bound.
- Verify backups exist for every database and important PVC.
- Verify app smoke tests: Auth, Nextcloud, Immich, Matrix, media stack, Attic/Nix cache.

Validation:

- `kubectl --context homelab-testing get pods -A` has no unexpected non-running pods.
- `flux --context homelab-testing get kustomizations -A` is all Ready.
- `flux --context homelab-testing get helmreleases -A` is all Ready.

### Phase 3: Storage Class Normalization

- Review app manifests for hardcoded storage class names.
- Replace hardcoded names with generic config keys where appropriate.
- Keep overlay-specific mappings in each cluster overlay.
- Document which app uses which logical storage class.

Validation:

- Render testing manifests and confirm storage classes resolve to `testing-longhorn-*`.
- Reconcile testing and verify PVCs remain Bound.

### Phase 4: Staging Release Candidate

- Promote cleaned testing state to `develop`.
- Restore and validate staging API access.
- Reconcile staging from `develop`.
- Fix staging-only drift without changing testing semantics.

Validation:

- Staging reaches the same Ready state as testing.
- Staging uses staging domains, staging secrets, and staging-sized PVCs.

### Phase 5: Production Release

- Promote validated staging state to `main`.
- Add production S3 backup credentials before enabling backup-dependent manifests.
- Decide whether prod should use branch `main` or a pinned production tag.
- Reconcile production.
- Tag the release only after production converges.

Validation:

- Production Flux sources reference `main` or the selected tag.
- Production Kustomizations and HelmReleases are Ready.
- Longhorn volumes are healthy.
- Backup jobs succeed.

## Release Gate Checklist

A cluster is releasable only when:

- Kubernetes API is reachable.
- All nodes are Ready.
- Flux sources are on the expected branch or tag.
- Flux Kustomizations are Ready.
- HelmReleases are Ready.
- No current pods are unexpectedly `Error`, `CrashLoopBackOff`, `ContainerCreating`, `ImagePullBackOff`, or `Pending`.
- PVCs are Bound.
- Longhorn volumes are Healthy.
- Database backups are configured and have a recent successful backup.
- Required SOPS secrets exist in the environment overlay.
- Smoke tests pass for user-facing services.

## Open Questions

- Should production Flux track `main` directly or a manually advanced production tag?
- Should staging mirror production storage topology exactly, or only app topology?
- Should backups use one S3 credential per app or one credential per environment with bucket-level separation?
- Should testing keep deliberately experimental apps, or should experiments move to feature overlays disabled by default?
- Should Longhorn replica defaults remain `1` until there are at least three stable storage nodes?
