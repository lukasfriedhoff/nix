# Secrets Routing Pattern

This document explains the `secretsByProfile` pattern used to route encrypted secrets
to the correct hosts.

## The nix-secrets split

Encrypted secrets no longer live in this repository. They moved to the private
repo [github.com/lukasfriedhoff/nix-secrets](https://github.com/lukasfriedhoff/nix-secrets),
which this flake consumes as the `nix-secrets` input (`git+ssh`, `flake = false`):

```nix
nix-secrets.url = "git+ssh://git@github.com/lukasfriedhoff/nix-secrets?ref=main&shallow=1";
nix-secrets.flake = false;
```

Key consequences:

- This repo has **no `secrets/` directory and no `.sops.yaml`**. The private
  repo keeps the old layout (`secrets/profiles/{common,personal,work}/...`)
  with `.sops.yaml` at its root, so all existing `path_regex` rules still match.
- `flake.nix` derives all secret roots from
  `${inputs.nix-secrets}/secrets/profiles`.
- Scripts resolve the local checkout via the `NIX_SECRETS_DIR` env var,
  defaulting to `../nix-secrets` next to this repo (see `secrets_root()` in
  `scripts/lib/common.sh`). Manual `sops` commands are run against that
  checkout.
- CI fetches the input with a read-only deploy key stored as the
  `NIX_SECRETS_DEPLOY_KEY` repository secret.
- Age key locations: desktops use `~/.config/sops/age/keys.txt` (bootstrapped
  to `/var/lib/sops-nix/age/keys.txt`), servers use
  `/var/lib/sops-nix/age/keys.txt`.

All `secrets/profiles/...` paths in the rest of this document (and the other
docs) refer to paths **inside the nix-secrets repo**.

## Overview

Secrets are organized by profile (personal/work) and role (desktop/server), with each
host receiving a tailored set of secret paths via `specialArgs`.

## Directory Structure

In the nix-secrets repo:

```
secrets/profiles/
├── common/
│   └── shared/              # Cross-profile secrets (currently unused)
├── personal/
│   ├── desktops/
│   │   ├── common/          # Shared desktop secrets (SSH keys)
│   │   ├── tux-h4xx-01/     # tux-specific secrets
│   │   ├── tab-h4xx-02/     # tab-specific secrets
│   │   └── lenovo-h4xx-03/  # lenovo-specific secrets
│   ├── servers/
│   │   ├── srv1/            # srv1 secrets
│   │   ├── srv2/            # srv2 secrets
│   │   ├── srv3/            # srv3 secrets
│   │   ├── srv4-vm-01/      # srv4 secrets
│   │   └── ceph/            # Ceph cluster secrets (by FSID)
│   │       └── <fsid>/
│   └── shared/              # Personal profile shared secrets
└── work/
    ├── desktops/
    │   └── macbook-pro/     # MacBook secrets
    ├── servers/
    │   ├── docker-host-01/
    │   └── timebutler-test-vm/
    └── shared/              # Work profile shared secrets
```

## The secretsByProfile Map

In `flake.nix`, each host profile maps to a set of secret directories rooted in
the nix-secrets input. Personal profiles all share one shape, built by
`mkPersonalSecrets` (via `mkPersonalDesktopSecrets` / `mkPersonalServerSecrets`):

```nix
profilesRoot = "${inputs.nix-secrets}/secrets/profiles";

mkPersonalSecrets = primary: {
  inherit primary;                                     # Host-specific
  shared = sharedCommonRoot;                           # Cross-profile
  profileShared = personalSharedRoot;                  # Personal profile shared
  profileCommon = personalCommonDesktopRoot;           # Personal desktop common
  root = primary;                                      # Alias for primary
  personal = primary;                                  # Personal alias
};

secretsByProfile = nixpkgs.lib.genAttrs homelabHosts mkPersonalServerSecrets // {
  tux = mkPersonalDesktopSecrets "tux-h4xx-01";
  mac = mkWorkSecrets "${workProfileRoot}/desktops/macbook-pro";
  # ... other hosts
};
```

## Usage in Modules

Host configurations receive secrets via `specialArgs`:

```nix
# In host configuration.nix
{ secrets, ... }:
{
  sops.secrets."wireguard-homelab-priv" = {
    sopsFile = "${secrets.primary}/wireguard/homelab.priv";
    owner = "root";
    format = "binary";
  };

  sops.secrets."wireguard-domain" = {
    sopsFile = "${secrets.profileShared}/wireguard/domain.txt";
  };

  sops.secrets."shared-secret" = {
    sopsFile = "${secrets.shared}/some-secret.yaml";
  };
}
```

## Secret Path Resolution

The pattern supports multiple resolution strategies:

1. **Direct path**: `secrets.primary` → host-specific directory
2. **Shared path**: `secrets.shared` → cross-profile secrets
3. **Profile shared**: `secrets.profileShared` → profile-level shared
4. **Profile common**: `secrets.profileCommon` → personal desktop common material

## Adding a New Host

1. Create the secret directory in the nix-secrets checkout:
   ```bash
   mkdir -p "${NIX_SECRETS_DIR:-../nix-secrets}/secrets/profiles/<profile>/<type>/<hostname>"
   ```

2. Add to `secretsByProfile` in `flake.nix` (homelab hosts whose flake attr,
   secrets profile, and host directory share one name only need an entry in
   the `homelabHosts` list):
   ```nix
   newhost = mkPersonalServerSecrets "<hostname>";  # or mkPersonalDesktopSecrets / mkWorkSecrets
   ```

3. Update the `.sops.yaml` at the nix-secrets repo root with the host's Age public key:
   ```yaml
   keys:
     - &newhost age1...
   creation_rules:
     - path_regex: secrets/profiles/<profile>/<type>/<hostname>/.*
       key_groups:
         - age:
             - *newhost
   ```

## Profile Types

| Profile | Description | Hosts |
|---------|-------------|-------|
| personal | Personal infrastructure | tux, tab, lenovo, srv4, srv1, srv2, srv3, srv5-k3s-stg1, srv6-k3s-stg2, srv7-k3s-stg3, srv8, srv9, testingrke2-01..03 |
| work | Customer/work infrastructure | mac, docker-host-01, timebutler-test-vm |

## Best Practices

1. **Minimal exposure**: Each host only sees secrets it needs
2. **Hierarchy**: Use shared directories for common secrets
3. **Naming**: Use descriptive names matching the secret's purpose
4. **Binary format**: Use `format = "binary"` for raw files (keys, certs)
5. **YAML format**: Use YAML for structured secrets with multiple fields
