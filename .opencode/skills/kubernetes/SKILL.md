---
name: kubernetes
description: Kubernetes resources, patterns, and kubectl operations
globs:
  - "**/*.yaml"
  - "**/*.yml"
  - "**/k8s/**"
  - "**/kubernetes/**"
  - "**/manifests/**"
---

# Kubernetes Skill

Kubernetes resource management and best practices.

## Core Resources

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: default
  labels:
    app: myapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: app
        image: myapp:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
```

## kubectl Commands

```bash
kubectl get pods -A                    # All pods
kubectl describe pod <name>            # Pod details
kubectl logs -f <pod>                  # Stream logs
kubectl exec -it <pod> -- bash         # Shell into pod
kubectl apply -f manifest.yaml         # Apply config
kubectl delete -f manifest.yaml        # Delete resources
kubectl rollout restart deploy/<name>  # Restart deployment
kubectl port-forward svc/<name> 8080   # Port forward
```

## Contexts & Namespaces

```bash
kubectl config get-contexts
kubectl config use-context <name>
kubectl config set-context --current --namespace=<ns>
```

## Resource Types

- Deployment, StatefulSet, DaemonSet - Workloads
- Service, Ingress - Networking
- ConfigMap, Secret - Configuration
- PVC, PV, StorageClass - Storage
- ServiceAccount, Role, RoleBinding - RBAC

## Best Practices

- Always set resource requests/limits
- Use namespaces for isolation
- Label everything consistently
- Use liveness/readiness probes
