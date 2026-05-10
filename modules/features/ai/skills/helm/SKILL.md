---
name: helm
description: Helm charts, values, and templating
globs:
  - "**/Chart.yaml"
  - "**/values.yaml"
  - "**/templates/**"
  - "**/charts/**"
---

# Helm Skill

Kubernetes package management with Helm.

## Chart Structure

```
mychart/
├── Chart.yaml          # Chart metadata
├── values.yaml         # Default values
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── _helpers.tpl    # Template helpers
│   └── NOTES.txt       # Post-install notes
└── charts/             # Dependencies
```

## Chart.yaml

```yaml
apiVersion: v2
name: myapp
version: 1.0.0
appVersion: "1.0"
dependencies:
  - name: postgresql
    version: "12.x.x"
    repository: https://charts.bitnami.com/bitnami
```

## Templating

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  {{- with .Values.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 8 }}
  {{- end }}
```

## Commands

```bash
helm repo add <name> <url>
helm repo update
helm search repo <keyword>
helm install <release> <chart> -f values.yaml
helm upgrade <release> <chart>
helm rollback <release> <revision>
helm uninstall <release>
helm template <chart>              # Render locally
helm lint <chart>                  # Validate chart
```

## Best Practices

- Use semantic versioning for charts
- Document all values in values.yaml
- Use _helpers.tpl for reusable templates
- Test with `helm template` before deploying
