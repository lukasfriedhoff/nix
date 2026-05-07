---
name: cilium
description: Cilium CNI, network policies, and service mesh
globs:
  - "**/cilium/**"
  - "**/*networkpolicy*.yaml"
  - "**/*ciliumnetworkpolicy*.yaml"
---

# Cilium Skill

eBPF-based networking, security, and observability.

## CiliumNetworkPolicy

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-web
spec:
  endpointSelector:
    matchLabels:
      app: web
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
  egress:
    - toEndpoints:
        - matchLabels:
            app: database
      toPorts:
        - ports:
            - port: "5432"
```

## Hubble (Observability)

```bash
hubble status
hubble observe --namespace default
hubble observe --pod myapp --follow
hubble observe --verdict DROPPED
```

## CLI Commands

```bash
cilium status
cilium connectivity test
cilium endpoint list
cilium policy get
cilium monitor                    # Live traffic
```

## L7 Policies

```yaml
ingress:
  - toPorts:
      - ports:
          - port: "80"
        rules:
          http:
            - method: GET
              path: "/api/.*"
```

## Cluster Mesh

```yaml
apiVersion: cilium.io/v2alpha1
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: cross-cluster
spec:
  endpointSelector: {}
  ingress:
    - fromEntities:
        - cluster
```

## Best Practices

- Start with default deny policies
- Use labels consistently for policy selection
- Enable Hubble for visibility
- Test policies in audit mode first
