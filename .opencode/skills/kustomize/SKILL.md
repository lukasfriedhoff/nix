---
name: kustomize
description: Kustomize overlays and patches
globs:
  - "**/kustomization.yaml"
  - "**/kustomization.yml"
  - "**/base/**"
  - "**/overlays/**"
---

# Kustomize Skill

Kubernetes native configuration management.

## Structure

```
app/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── production/
    │   ├── kustomization.yaml
    │   └── replica-patch.yaml
    └── staging/
        └── kustomization.yaml
```

## kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: myapp

resources:
  - deployment.yaml
  - service.yaml

commonLabels:
  app: myapp

configMapGenerator:
  - name: app-config
    files:
      - config.json

secretGenerator:
  - name: app-secrets
    envs:
      - secrets.env

images:
  - name: myapp
    newTag: v1.2.3

patches:
  - path: replica-patch.yaml
```

## Patches

### Strategic Merge Patch
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 5
```

### JSON Patch
```yaml
patches:
  - target:
      kind: Deployment
      name: myapp
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 5
```

## Commands

```bash
kustomize build overlays/production
kubectl apply -k overlays/production
kubectl diff -k overlays/production
```

## Best Practices

- Keep base minimal and generic
- Use overlays for environment-specific config
- Prefer patches over duplication
- Use configMapGenerator for config files
