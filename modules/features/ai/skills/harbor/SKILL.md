---
name: harbor
description: Operating the Harbor container registry at harbor.h4xx.io — robot/CI auth, OIDC via Authelia, GitOps layout, push-size caveat, API patterns
---

# Harbor Registry Skill

Harbor 2.15 (chart harbor-helm 1.19.x) at **https://harbor.h4xx.io**, homelab-prod
only, namespace `harbor`. Deployed 2026-09-19.

## Where everything lives (GitOps)

- App: `flux-apps/apps/harbor/` — HelmRelease (chart values), CNPG `postgres.yaml`
  (cluster `harbor-postgres`, db `registry`, 3 instances on `longhorn-nvme-rwo-2r`),
  barman backup to `backup.h4xx.io:9000` MinIO + ScheduledBackup (03:00).
- Wiring: `flux-cluster/base/kustomizations/infra/harbor.yaml` (Kustomization
  `harbor-app`, suspended by default; homelab overlay sets `harbor_suspend: "false"`).
  Vars: `harbor_*` in `base-config.yaml` + `overlays/homelab/cluster-patch.yaml`.
- Secrets (SOPS, `flux-cluster/overlays/homelab/secrets/`):
  - `harbor-admin.yaml` → local admin password (`HARBOR_ADMIN_PASSWORD`)
  - `harbor-oidc.yaml` → key `oidc-config`, a JSON blob injected via HelmRelease
    `valuesFrom` → `core.configureUserSettings` → `CONFIG_OVERWRITE_JSON`
  - `harbor-postgres-backup-credentials.yaml`

## Auth model

- **OIDC via Authelia** (`auth_mode: oidc_auth`): client `harbor` in
  `flux-apps/apps/authelia/configmap.yaml`, digest in `authelia-oidc.yaml`
  (key `identity_providers.oidc.client.harbor.secret`, bcrypt). Callback:
  `https://harbor.h4xx.io/c/oidc/callback`. Group claim `groups`; members of the
  LLDAP group **`harbor-admins`** become Harbor admins (auto-onboard on).
  Settings pushed via CONFIG_OVERWRITE_JSON are **read-only in the UI** — change
  them in the `harbor-oidc.yaml` SOPS secret, then restart harbor-core.
- **Local admin fallback**: `https://harbor.h4xx.io/account/sign-in` (username
  `admin`, password from the `harbor-admin` secret) keeps working with OIDC on.
- **CI / automation / AI**: system robot **`robot$ci`** (never expires; push,
  pull, scan, tag, delete on all projects). Credentials live in **nix-secrets**:
  `secrets/profiles/personal/shared/harbor/ci-robot.yaml`
  (`harbor.robot_name` / `harbor.robot_secret`). Read with:
  ```bash
  sops -d ~/git/lukasfriedhoff/nix-secrets/secrets/profiles/personal/shared/harbor/ci-robot.yaml
  # docker/podman/crane login:
  #   user:     robot$ci     (the $ is part of the name — quote it in shells!)
  #   password: <robot_secret>
  ```
  In Kubernetes, robot creds go into `kubernetes.io/dockerconfigjson` pull
  secrets. New robots: `POST /api/v2.0/robots` as admin (`level: system`,
  `duration: -1`); the secret is shown ONCE in the response.

## Traps

- **`robot$ci` contains `$`** — single-quote it (`-u 'robot$ci:...'`) or shells
  expand `$ci` to empty and auth fails with a confusing 401.
- **Push size over the Cloudflare tunnel**: harbor.h4xx.io ingresses through
  cloudflared; CF caps request bodies (~100MB) → **large layer pushes fail**.
  Pulls and UI are fine. For real push traffic add a LAN path (traefik is
  ClusterIP-only today — needs NodePort/LB + MikroTik split-horizon DNS static).
- **External CNPG DB**: chart reads the CNPG-generated `harbor-postgres-app`
  secret directly (it has the required `password` key). The database `registry`
  is created by CNPG initdb — Harbor only migrates schema. Don't rename the DB:
  `database.external.coreDatabase` must match CNPG `initdb.database`.
- **RWO PVCs + upgrades**: HelmRelease sets `updateStrategy.type: Recreate`
  (RollingUpdate deadlocks on Longhorn RWO). Expect ~30s downtime on upgrades.
- **jobservice crashloops at first install** until harbor-core serves — it's
  startup ordering, not a failure; it self-heals within 2 backoffs.
- **New DNS records not appearing** → check external-dns version FIRST
  (see external-dns-v022-regression memory).

## Useful API one-liners (admin)

```bash
PW=$(kubectl --context homelab-prod -n harbor get secret harbor-admin \
  -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d)
H="https://harbor.h4xx.io/api/v2.0"
curl -su "admin:$PW" $H/systeminfo | jq          # auth_mode, version
curl -su "admin:$PW" $H/projects | jq '.[].name'
curl -su "admin:$PW" $H/robots | jq '.[].name'
# proxy-cache project (e.g. docker hub mirror): create registry endpoint first
#   POST $H/registries {name, type: "docker-hub", url: "https://hub.docker.com"}
#   POST $H/projects   {project_name, registry_id, metadata: {public: "true"}}
```

## Health

- All pods in ns `harbor`; CNPG: `kubectl get cluster harbor-postgres -n harbor`.
- `curl -s https://harbor.h4xx.io/api/v2.0/ping` → `Pong`.
- Trivy is default scanner; scan-on-push configurable per project.
