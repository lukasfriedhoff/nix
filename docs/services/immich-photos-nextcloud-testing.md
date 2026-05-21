# Immich Photos + Nextcloud Link (Testing)

This runbook deploys a **second isolated Immich instance** for photos (`immich-photos`) and links it into Nextcloud as an External Site.

## Scope

- Cluster: `homelab-testing` (`testing-srv3`)
- New app namespace: `immich-photos`
- Public URL: `https://photos-testing.h4xx.io`
- Nextcloud link label: `Photos`

## GitOps design

- `flux-apps` remains cluster-agnostic:
  - app manifests in `apps/immich-photos`
  - defaults/examples in `examples/apps/immich-photos`
  - Nextcloud hook config driven by variables only
- `flux-cluster` testing overlay only provides deltas:
  - enables the new app
  - sets testing storage/backup endpoints
  - provides testing secrets in `overlays/testing-srv3/secrets`

## Variables used

### Base (`flux-cluster/base/base-config.yaml`)

- `immich_photos_*` keys for image/resources/storage/backup
- `nextcloud_external_photos_enabled`
- `nextcloud_external_photos_url`
- `nextcloud_external_photos_label`

### Testing overlay (`flux-cluster/overlays/testing-srv3/cluster-patch.yaml`)

- `immich_photos_suspend: "false"`
- testing Longhorn classes and PVC sizes
- `immich_photos_postgres_backup_endpoint_url: http://storage01.storage.lab.h4xx.io:9000`
- `nextcloud_external_photos_enabled: "true"`
- `nextcloud_external_photos_url: https://photos-testing.h4xx.io`

## Secrets (testing overlay)

Added to `flux-cluster/overlays/testing-srv3/secrets/`:

- `immich-photos-secrets.yaml`
- `immich-photos-postgres-app.yaml`
- `immich-photos-postgres-backup-credentials.yaml`

And referenced in:

- `flux-cluster/overlays/testing-srv3/secrets/kustomization.yaml`

## Rollout commands

Run from your workstation:

```bash
# 1) Push flux-apps changes first
cd ~/git/lukasfriedhoff/flux-apps
git add apps/immich-photos apps/nextcloud examples/apps/immich-photos examples/apps/nextcloud
git commit -m "feat(immich): add second immich-photos app and nextcloud external-site integration"
git push

# 2) Push flux-cluster overlay/base wiring
cd ~/git/lukasfriedhoff/flux-cluster
git add base overlays/testing-srv3
git commit -m "feat(testing): enable immich-photos app and wire testing secrets/config"
git push

# 3) Reconcile testing cluster
flux --context=homelab-testing reconcile source git flux-apps
flux --context=homelab-testing reconcile source git flux-cluster
flux --context=homelab-testing reconcile kustomization secrets --with-source
flux --context=homelab-testing reconcile kustomization kustomizations --with-source
flux --context=homelab-testing get kustomizations
```

## Validation commands

```bash
# App health
kubectl --context=homelab-testing -n immich-photos get all
kubectl --context=homelab-testing -n immich-photos get pvc
kubectl --context=homelab-testing -n immich-photos get cluster,scheduledbackup

# Nextcloud external-site config
kubectl --context=homelab-testing -n nextcloud exec deploy/nextcloud -- \
  php /var/www/html/occ config:app:get external sites

# Ingress endpoint check
curl -I https://photos-testing.h4xx.io
```

Expected:

- `immich-photos` pods ready
- CNPG cluster `immich-photos-postgres` ready
- Nextcloud external sites JSON contains an entry with URL `https://photos-testing.h4xx.io`

