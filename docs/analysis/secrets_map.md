# Secrets layout, recipients, and decryption scope

Source of truth: `.sops.yaml` `creation_rules` and current directory layout under `secrets/profiles/`.

## Recipient key owners (human-readable)
- **tux-h4xx-01**: personal desktop (age16aay…)
- **tab-h4xx-02**: personal laptop/tablet (age192f9…)
- **lenovo-h4xx-03**: personal desktop (age1r773…)
- **srv4-vm-01**: personal server key labeled `srv4` (age1yff2…)
- **srv1**: homelab server (age1qms8…)
- **srv2**: homelab server (age1jgca…)
- **srv8**: homelab server (age1f4w9…)
- **macbook-pro**: work desktop (age1dqt5…)

## Markdown tree: paths, who can decrypt, and why

```
secrets/profiles/
├── common/
│   └── shared/                          [tux, tab, lenovo, srv4, macbook-pro]
│       (reserved for cross-profile secrets)
├── personal/
│   ├── shared/                          [tux, tab, lenovo, srv4, srv1, srv2, srv8]
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
│   └── servers/                         [tux, tab, lenovo, srv4, srv1, srv2, srv8]
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
│       ├── srv3/
│       │   ├── flux-cluster-bootstrap-token.txt
│       │   └── nix-cache/
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
- **personal/shared**: used across personal desktops and homelab infra; srv1, srv2, and srv8 are included for server-side automation.
- **personal/desktops/**: per-desktop secrets restricted to the specific device; `ssh` subtrees are shared between personal desktops for admin convenience.
- **personal/servers/**: decryptable by personal desktops plus homelab server keys so both admins and server automation can access.
- **work/shared, work/desktops, work/servers**: work-only scope, decryptable solely by the work macbook.

## Host-specific notes
- **Ceph on `tux-h4xx-01`**: this desktop is a Ceph client for the homelab cluster. It stores a client keyring under `secrets/profiles/personal/desktops/tux-h4xx-01/ceph/` so the system can mount/access RBDs and the user can run CLI tools (`rbd`, `rados`) without manual key distribution. This is why a desktop-scoped Ceph secret exists.

## Authelia test user lookup
- **Testing cluster**: `secrets/profiles/personal/shared/authelia/testing-srv3-testuser.yaml`
- **Staging cluster**: `secrets/profiles/personal/shared/authelia/staging-3vm-testuser.yaml`
- These files hold the canonical `testuser` credentials for environment login checks.

## Policy notes
- **WireGuard secrets are personal-only**: shared domain/endpoint live under `personal/shared/wireguard` so work hosts do not receive decryption keys.

## Rule notes and precedence
- `creation_rules` are evaluated top-to-bottom; the first matching `path_regex` applies.
- The special SSH rules under `personal/desktops/**/ssh/` intentionally narrow access to personal desktops only.

## Follow-ups
- If new hosts are added, update `.sops.yaml` recipients and this map.
- Consider adding a small script to regenerate this tree from `.sops.yaml` + `secrets/profiles/`.
