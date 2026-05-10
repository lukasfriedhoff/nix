---
name: cert-manager
description: Certificate management and Let's Encrypt
globs:
  - "**/*issuer*.yaml"
  - "**/*certificate*.yaml"
  - "**/cert-manager/**"
---

# Cert-Manager Skill

Automated certificate management for Kubernetes.

## ClusterIssuer (Let's Encrypt)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: nginx
      - dns01:
          cloudflare:
            email: admin@example.com
            apiTokenSecretRef:
              name: cloudflare-token
              key: api-token
```

## Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: myapp-tls
  namespace: default
spec:
  secretName: myapp-tls-secret
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - myapp.example.com
    - www.myapp.example.com
  duration: 2160h    # 90 days
  renewBefore: 360h  # 15 days
```

## Ingress Annotation

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts:
        - myapp.example.com
      secretName: myapp-tls
```

## Commands

```bash
kubectl get certificates -A
kubectl describe certificate <name>
kubectl get certificaterequests -A
cmctl status certificate <name>
cmctl renew <name>
```

## Best Practices

- Use staging issuer for testing
- Set appropriate renewBefore
- Use DNS01 for wildcard certs
- Monitor certificate expiration
