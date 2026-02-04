# Secrets Routing Pattern

This document explains the `secretsByProfile` pattern used to route encrypted secrets
to the correct hosts.

## Overview

Secrets are organized by profile (personal/work) and role (desktop/server), with each
host receiving a tailored set of secret paths via `specialArgs`.

## Directory Structure

```
secrets/profiles/
├── common/
│   └── shared/              # Cross-profile secrets (currently unused)
├── personal/
│   ├── desktops/
│   │   ├── common/          # Shared desktop secrets (SSH keys)
│   │   ├── tux-h4xx-01/     # tux-specific secrets
│   │   └── tab-h4xx-02/     # tab-specific secrets
│   ├── servers/
│   │   ├── srv1/            # srv1 secrets
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

In `flake.nix`, each host profile maps to a set of secret directories:

```nix
secretsByProfile = {
  tux = {
    primary = personalDesktopRoot "tux-h4xx-01";      # Host-specific
    shared = sharedCommonRoot;                         # Cross-profile
    profileShared = personalSharedRoot;                # Personal profile shared
    profileCommon = personalCommonDesktopRoot;         # Personal desktop common
    ceph = "${personalProfileRoot}/servers/ceph";      # Ceph secrets
    root = personalDesktopRoot "tux-h4xx-01";          # Alias for primary
    personal = personalDesktopRoot "tux-h4xx-01";      # Personal alias
  };
  mac = {
    primary = workDesktopRoot "macbook-pro";
    shared = sharedCommonRoot;
    profileShared = workSharedRoot;
    root = workDesktopRoot "macbook-pro";
    dacoso = workDesktopRoot "macbook-pro";            # Work alias
  };
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
4. **Service-specific**: `secrets.ceph` → Ceph cluster secrets

## Adding a New Host

1. Create secret directory:
   ```bash
   mkdir -p secrets/profiles/<profile>/<type>/<hostname>
   ```

2. Add to `secretsByProfile` in `flake.nix`:
   ```nix
   newhost = {
     primary = <profile><Type>Root "<hostname>";
     shared = sharedCommonRoot;
     profileShared = <profile>SharedRoot;
     # ... additional paths as needed
   };
   ```

3. Update `.sops.yaml` with the host's Age public key:
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
| personal | Personal infrastructure | tux, tab, srv1, srv4 |
| work | Customer/work infrastructure | mac, docker-host-01 |

## Best Practices

1. **Minimal exposure**: Each host only sees secrets it needs
2. **Hierarchy**: Use shared directories for common secrets
3. **Naming**: Use descriptive names matching the secret's purpose
4. **Binary format**: Use `format = "binary"` for raw files (keys, certs)
5. **YAML format**: Use YAML for structured secrets with multiple fields
