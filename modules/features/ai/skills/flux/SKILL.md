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
