---
name: flux
description: FluxCD GitOps toolkit and reconciliation
globs:
  - "**/flux/**"
  - "**/flux-system/**"
  - "**/*kustomization*.yaml"
  - "**/helmrelease*.yaml"
  - "**/gitrepository*.yaml"
---

# FluxCD Skill

GitOps continuous delivery with FluxCD.

## Core Resources

### GitRepository
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/org/repo
  ref:
    branch: main
  secretRef:
    name: git-credentials
```

### Kustomization
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 10m
  path: ./apps
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: myapp
      namespace: default
```

### HelmRelease
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: myapp
spec:
  interval: 5m
  chart:
    spec:
      chart: myapp
      version: "1.0.0"
      sourceRef:
        kind: HelmRepository
        name: myrepo
  values:
    key: value
```

## Commands

```bash
flux check                           # Verify installation
flux get all -A                      # All resources
flux reconcile kustomization <name>  # Force sync
flux logs --all-namespaces           # View logs
flux suspend/resume <type> <name>    # Pause/unpause
```

## Structure

```
clusters/
├── production/
│   ├── flux-system/      # Flux components
│   ├── infrastructure/   # Shared infra
│   └── apps/             # Application workloads
└── staging/
```

## Best Practices

- Use `prune: true` to clean up removed resources
- Set health checks for critical deployments
- Use dependsOn for ordering
- Store secrets with SOPS or sealed-secrets

## Operating live workloads — suspend, scale, quiesce (READ BEFORE `kubectl scale`)

**The reconciliation layers own their objects. Imperative `kubectl` edits are drift and get reverted.**

```
GitRepository ──(source-controller fetches)
  └─ Kustomization ──(kustomize-controller applies manifests, incl. HelmRelease CRs)
       └─ HelmRelease ──(helm-controller renders chart, applies Deployments/StatefulSets/CronJobs/Jobs)
            └─ Deployment / CronJob / Job  ← the objects you see with kubectl
```

Whichever controller **owns** an object continuously reconciles it back to the
declared spec, usually within its `interval` (often 1–10 min). So:

- `kubectl scale deploy/... --replicas=0`, `kubectl edit`, `kubectl patch cronjob ... suspend=true`
  on a **Flux-managed** object are **temporary** — the owning controller reverts
  them on its next reconcile. You will see a pod you "scaled to 0" reappear minutes later.

### The trap that bites: suspending the Kustomization ≠ quiescing HR-managed apps
If an app is deployed by a **HelmRelease** (the common case — e.g. `app-template`),
`flux suspend kustomization <name>` only stops the *Kustomization* from re-applying
the HelmRelease **CR**. The **helm-controller keeps reconciling the existing
HelmRelease** and will restore Deployment replicas and re-create/unsuspend CronJobs.
Suspending the Kustomization does **not** pause the workload.

### Correct way to quiesce a workload
1. Find what owns it: `flux get helmreleases -A` / `flux tree kustomization <name> -n flux-system`.
2. **Suspend at the owning layer:**
   - App is a HelmRelease → `flux suspend helmrelease <name> -n <ns>` (loop over all
     per-app HRs to quiesce a whole stack).
   - Resource applied *directly* by a Kustomization (raw manifest, no HR) →
     `flux suspend kustomization <name> -n flux-system`.
3. **Then** do the imperative change — now it sticks:
   `kubectl scale deploy --all --replicas=0 -n <ns>` and, for HR-owned CronJobs,
   `kubectl patch cronjob <c> -p '{"spec":{"suspend":true}}'` (only holds once the HR is suspended).
4. Kill leftover Job pods the HR spawned (they won't be recreated while the HR is suspended).

### Resume
`flux resume helmrelease <name> -n <ns>` → the helm-controller reconciles back to the
**git-declared** state (restores replicas, re-enables CronJobs). If you changed replicas
in git, resume applies the git value — not your imperative one.

### GitOps-native alternative (prefer for anything lasting)
Don't fight the controllers imperatively. Put the desired state in **git**
(`spec.suspend: true` on the HR, or the replica/values change) and let Flux apply it.
Imperative `kubectl` is only appropriate for a short, controller-suspended maintenance window.

**Rule of thumb:** before any `kubectl scale`/`edit`/`patch` on a cluster app, ask
"what Flux resource owns this?" and suspend *that* first — or your change is a no-op
on a timer.

## This homelab's layering (flux-cluster) — read before adding or pausing an app

The Kustomization objects are themselves Flux-managed, one level above the apps.
On prod the chain is:

```
Kustomization/homelab        path ./overlays/homelab/        ← applies base-config ConfigMap + secrets
  └─ Kustomization/kustomizations   path ./overlays/homelab/kustomizations/
        (which `resources:` ../../../base/kustomizations/ + overlay-only entries)
        └─ Kustomization/<app>-app  path ./apps/<app> in flux-apps   ← applies the workload
```

Find the owner of *any* object (this is the fastest way to answer "who reverts my edit?"):

```bash
kubectl -n <ns> get <kind>/<name> \
  -o jsonpath='{.metadata.labels.kustomize\.toolkit\.fluxcd\.io/name}{"\n"}'
# base-config  -> homelab
# <app>-app    -> kustomizations
```

### Trap: a new app file in `base/kustomizations/infra/` does nothing
`base/kustomizations/kustomization.yaml` is an **explicit `resources:` list**, not a
directory glob. Drop in `infra/<app>.yaml`, commit, reconcile — and
`flux get kustomization <app>-app` still says *not found*, with no error anywhere.
Register the file in that list too. (`infra/moonlight-web.yaml` sits commented out
there — which is why that app has never deployed, not a bug in the app.)

### Trap: `flux suspend kustomization <app>-app` does not hold
The `<app>-app` **object** is owned by `kustomizations`, whose git copy carries
`spec.suspend: ${<app>_suspend:=true}` → substituted to `false`. Your suspend is
drift: the parent re-applies `suspend: false` on its next reconcile (minutes), and
the app comes back mid-debug. To actually pause an app:

- **Short maintenance window:** `flux suspend kustomization kustomizations` (the
  *parent*) — note this freezes every app's Kustomization, so keep it brief.
- **Lasting:** set `<app>_suspend: "true"` in the overlay's `cluster-patch.yaml`
  and push. GitOps-native, survives everything.

Same idea as the HelmRelease trap above, one layer up: suspend the thing that
*writes* the object, not the object itself.

### Trap: changing a `${var}` needs the ConfigMap's owner reconciled
`postBuild.substituteFrom` reads the **live** `base-config` ConfigMap. Push a new
value (image tag, storage class) and reconcile only the app, and Flux substitutes
the **old** value — the new manifest gets the stale var. The classic symptom is an
`ImagePullBackOff` for a reference you never wrote (new repo name + old tag).

```bash
flux reconcile kustomization homelab --with-source   # refreshes base-config FIRST
kubectl -n flux-system get cm base-config -o jsonpath='{.data.<var>}{"\n"}'  # verify
flux reconcile kustomization <app>-app               # then the app
```

### Reconcile order for a change that spans repos

```bash
flux reconcile source git flux-cluster               # 1. cluster wiring
flux reconcile source git flux-apps                  # 2. app manifests
flux reconcile kustomization homelab --with-source   # 3. vars/secrets (base-config)
flux reconcile kustomization kustomizations          # 4. app Kustomization objects
flux reconcile kustomization <app>-app --with-source # 5. the app itself
```

`flux reconcile kustomization <parent>` blocks on **health checks of every child**
(`wait: true`), so it routinely times out with "dependency … is not ready" while an
unrelated app is mid-rollout. That is not a failure of your change — check the named
child, or check your app directly instead of trusting the parent's exit code.
