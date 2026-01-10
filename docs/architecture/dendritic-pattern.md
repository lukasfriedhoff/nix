# Dendritic Nix Pattern

This document evaluates the Dendritic pattern for potential adoption in this repository.

## What is Dendritic?

Dendritic is an architectural pattern for organizing NixOS, Home Manager, and nix-darwin
configurations where:

- Every Nix file is a top-level module imported directly into flake-parts
- Files are organized by feature/concern rather than by type
- Values are shared via let-bindings at the flake-parts level (no specialArgs chains)

**References:**
- [mightyiam/dendritic](https://github.com/mightyiam/dendritic)
- [Dendrix distribution](https://dendrix.oeiuwq.com/Dendritic.html)

## Current Approach vs Dendritic

### Current Organization (by type)

```
modules/nixos/
├── profiles/          # Role-based configs
│   ├── desktop/
│   ├── server/
│   └── homelab/
├── services/          # Service modules
│   ├── ceph.nix
│   ├── kvm.nix
│   └── wireguard-homelab.nix
└── hardware/          # Hardware configs
    ├── tuxedo/
    └── asus/

home/
├── programs/          # User programs
│   ├── dev/
│   ├── devops/
│   └── utils/
└── platforms/         # OS-specific
```

### Dendritic Organization (by feature)

```
modules/
├── ceph/              # All Ceph-related config
│   ├── nixos.nix      # NixOS service
│   ├── home.nix       # User tools (ceph CLI)
│   └── shared.nix     # Shared values
├── kubernetes/
│   ├── nixos.nix      # k3s config
│   └── home.nix       # kubectl, k9s
├── git/
│   ├── home.nix       # Git config
│   └── shared.nix     # Gitignore patterns
└── ...
```

## Comparison

| Aspect | Current | Dendritic |
|--------|---------|-----------|
| Module discovery | Manual import lists | Auto-import from tree |
| Value sharing | specialArgs chains | Flake-parts let-bindings |
| Organization | By config type | By feature/concern |
| Cross-config coherence | Scattered files | Single feature directory |
| Boilerplate | Module lists per host | Minimal, auto-discovered |

## Benefits of Dendritic

1. **Reduced boilerplate**: No manual module lists to maintain
2. **Feature cohesion**: All related config in one place
3. **Easier navigation**: Find everything about "Ceph" in one directory
4. **Simpler value sharing**: No specialArgs plumbing

## Challenges of Migration

1. **Significant restructure**: Would require moving many files
2. **Learning curve**: Different mental model for organization
3. **Current setup works**: Already well-organized and maintainable
4. **Partial adoption**: Hard to adopt incrementally

## Recommendation

**Keep current structure with incremental improvements.**

### Why Not Full Adoption

1. Current organization is clear and works well
2. Migration effort outweighs benefits for this repository size
3. specialArgs pattern is well-established and documented

### Adopted Concepts

We've incorporated some Dendritic ideas:

1. **Category organization** in `home/programs/`:
   ```
   programs/
   ├── dev/       # Development tools
   ├── devops/    # Infrastructure tools
   ├── utils/     # Utilities
   └── work/      # Work-specific
   ```

2. **Auto-import helpers** in `lib/default.nix`:
   ```nix
   myLib.importSubdirs ./programs  # Import all category default.nix
   myLib.importTree ./modules      # Recursive import
   ```

3. **Shared library functions** centralized in `lib/`

## Future Considerations

If the repository grows significantly, consider:

1. **Feature directories** for complex features (Ceph, Kubernetes)
2. **Shared value files** per feature instead of specialArgs
3. **Auto-import** for all modules with option-based activation

## Example: Partial Dendritic for Ceph

If we wanted to adopt Dendritic for Ceph specifically:

```
modules/features/ceph/
├── nixos.nix          # services.ceph, lukasf.ceph options
├── home.nix           # ceph CLI tools for users
├── topology.nix       # Shared cluster topology
└── default.nix        # Imports all parts

# In flake.nix
modules = [
  ./modules/features/ceph
  # ...other features
];
```

This allows gradual adoption without full restructure.
