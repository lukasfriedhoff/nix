# Secrets layout, recipients, and decryption scope

Source of truth: the `.sops.yaml` `creation_rules` at the root of the private
[nix-secrets](https://github.com/lukasfriedhoff/nix-secrets) repo and the directory
layout under `secrets/profiles/` there. All paths below are relative to the local
nix-secrets checkout (`NIX_SECRETS_DIR`, default `../nix-secrets`); see
`docs/architecture/secrets-routing.md` for the repo split.

## Recipient key owners (human-readable)
- **tux-h4xx-01**: personal desktop (age16aay…)
- **tab-h4xx-02**: personal laptop/tablet (age192f9…)
- **lenovo-h4xx-03**: personal desktop (age1r773…)
- **srv4-vm-01**: personal server key labeled `srv4` (age1yff2…)
- **srv1**: homelab server (age1qms8…)
- **srv2**: homelab server (age1jgca…)
- **srv8**: homelab server (age1f4w9…)
- **testingrke2-01**: local RKE2 lab server (age1er8h…)
- **testingrke2-02**: local RKE2 lab server (age1xlw9…)
- **testingrke2-03**: local RKE2 lab server (age1n4wg…)
- **srv9**: homelab server (age1ewj9…)
- **macbook-pro**: work desktop (age1dqt5…)

## Markdown tree: paths, who can decrypt, and why

```
secrets/profiles/
├── common/
│   └── shared/                          [tux, tab, lenovo, srv4, macbook-pro]
│       (reserved for cross-profile secrets)
├── personal/
│   ├── shared/                          [tux, tab, lenovo, srv4, srv1, srv2, srv8, srv9]
│   │   ├── cloudflare/                  (Cloudflare API tokens for personal infra automation)
│   │   ├── authelia/                    (shared Authelia test users by environment/cluster)
│   │   ├── homelab/                     (shared personal homelab secrets)
│   │   │   └── flux-cluster-dev/
│   │   └── luks/                        (shared luks material)
│   │   └── wireguard/                   (personal-only WireGuard domain/endpoint)
│   ├── desktops/
│   │   ├── common/ssh/                  [tux, tab, lenovo]
│   │   │   (desktop SSH identities used by personal machines)
│   │   ├── tux-h4xx-01/                 [tux]
│   │   │   ├── ceph/
│   │   │   ├── ssh/                     [tux, tab] (ssh rule applies)
│   │   │   └── wireguard/
│   │   ├── lenovo-h4xx-03/              [lenovo]
│   │   │   └── wireguard/
│   │   └── tab-h4xx-02/                 [tab]
│   │       └── wireguard/
│   └── servers/                         [personal admins + homelab server automation keys]
│       ├── ceph/
│       │   └── 83897024-e964-11f0-9d5c-0cc47a6c3802/
│       ├── srv1/
│       │   ├── nix-cache/
│       │   ├── seaweedfs/
│       │   └── ssh/
│       ├── srv2/
│       │   └── ssh/
│       ├── srv8/
│       │   └── ssh/
│       ├── srv9/
│       │   ├── age.key
│       │   ├── k3s-server-token.txt
│       │   ├── login-password-hash.txt
│       │   └── ssh/
│       ├── srv3/
│       │   ├── flux-cluster-bootstrap-token.txt
│       │   └── nix-cache/
│       ├── testingrke2-01/
│       │   ├── age.key
│       │   ├── flux-cluster-bootstrap-token.txt
│       │   ├── flux-sops-age.key
│       │   ├── rke2-token.txt
│       │   └── ssh/
│       ├── testingrke2-02/
│       │   ├── age.key
│       │   ├── rke2-token.txt
│       │   └── ssh/
│       ├── testingrke2-03/
│       │   ├── age.key
│       │   ├── rke2-token.txt
│       │   └── ssh/
│       └── srv4-vm-01/
│           └── wireguard/
└── work/
    ├── shared/                          [macbook-pro]
    ├── desktops/
    │   └── macbook-pro/                 [macbook-pro]
    └── servers/                         [macbook-pro]
        ├── docker-host-01/
        └── timebutler-test-vm/
```

### Why each scope can decrypt
- **common/shared**: intended for secrets used by both personal and work setups, so both personal devices and the work desktop are recipients.
- **personal/shared**: used across personal desktops and homelab infra; srv1, srv2, srv8, and srv9 are included for server-side automation.
- **personal/desktops/**: per-desktop secrets restricted to the specific device; `ssh` subtrees are shared between personal desktops for admin convenience.
- **personal/servers/**: decryptable by personal desktops plus homelab server keys so both admins and server automation can access.
- **work/shared, work/desktops, work/servers**: work-only scope, decryptable solely by the work macbook.

## Host-specific notes
- **Ceph on `tux-h4xx-01`**: historical — the Ceph modules have been removed from the nix repo. The client keyring under `secrets/profiles/personal/desktops/tux-h4xx-01/ceph/` (and the cluster material under `personal/servers/ceph/<fsid>/`) still exists in nix-secrets but is no longer consumed by any module.
- **`testingrke2` lab**: each VM has an independent host Age key and management key. The three encrypted `rke2-token.txt` files contain the same cluster token in independent SOPS envelopes. Only `testingrke2-01` receives the Flux bootstrap token and Flux SOPS key because it owns the bootstrap unit.

## Authelia test user lookup
- **Testing cluster**: `secrets/profiles/personal/shared/authelia/testing-srv3-testuser.yaml`
- **Staging cluster**: `secrets/profiles/personal/shared/authelia/staging-3vm-testuser.yaml`
- **Production cluster**: `secrets/profiles/personal/shared/authelia/homelab-prod-testuser.yaml`
- These files hold the canonical `testuser` credentials for environment login checks.

## Policy notes
- **WireGuard secrets are personal-only**: shared domain/endpoint live under `personal/shared/wireguard` so work hosts do not receive decryption keys.

## Rule notes and precedence
- `creation_rules` are evaluated top-to-bottom; the first matching `path_regex` applies.
- The special SSH rules under `personal/desktops/**/ssh/` intentionally narrow access to personal desktops only.

## Follow-ups
- If new hosts are added, update the nix-secrets repo's `.sops.yaml` recipients and this map.
- Consider adding a small script to regenerate this tree from `.sops.yaml` + `secrets/profiles/` in the nix-secrets repo.
