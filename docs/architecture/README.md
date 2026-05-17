# Architecture Documentation

This directory contains architectural decisions and pattern documentation for the Nix monorepo.

## Documents

| Document | Description |
|----------|-------------|
| [secrets-routing.md](secrets-routing.md) | How secrets are routed to hosts via `secretsByProfile` |
| [nixos-facter.md](nixos-facter.md) | Evaluation of nixos-facter for hardware detection |
| [dendritic-pattern.md](dendritic-pattern.md) | Analysis of the Dendritic module organization pattern |

## Key Patterns

### Module Composition

Hosts are built from composable module sets defined in `flake.nix`:

```
coreModules            → Feature modules (`modules/features/**/nixos.nix`) + sops/comin/facter
├── baseDesktopModules → + stylix + Home Manager
│   ├── plasmaDesktopModules  → + KDE Plasma
│   └── gnomeDesktopModules   → + GNOME + laptop power management
├── baseServerModules  → + server defaults (+ dacoso defaults, for work servers)
└── homelabServerModules → + server defaults (homelab personal servers; no dacoso)
```

### Secret Routing

Each host receives a `secrets` attribute with paths to its encrypted secrets.
See [secrets-routing.md](secrets-routing.md) for details.

### Profile System

Hosts are assigned profiles that determine:
- Which secrets they can access
- Whether `workSystem = true` (affects SSH config, etc.)
- Default configuration values

Profiles: `tux`, `tab`, `lenovo`, `srv4`, `srv1`, `srv2`, `srv3`, `srv5-k3s-stg1`, `srv6-k3s-stg2`, `srv7-k3s-stg3`, `mac`, `docker-host-01`, `timebutler-test-vm`

### Library Functions

Custom import helpers in `lib/default.nix`:

```nix
myLib.importDir ./path      # Import all .nix files in directory
myLib.importSubdirs ./path  # Import subdirs with default.nix
myLib.importTree ./path     # Recursive import
myLib.importTreeByName ./modules/features "nixos.nix"
```

## Design Principles

1. **Declarative**: All configuration is in Nix, no imperative scripts for setup
2. **Reproducible**: Pinned dependencies via flake.lock
3. **Modular**: Small, focused modules that compose well
4. **Secure**: Secrets encrypted at rest, minimal exposure per host
5. **Documented**: Architecture decisions recorded for future reference
