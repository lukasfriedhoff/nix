# Dendritic Nix Pattern

This repository uses a Dendritic, feature-based module layout.

## What is Dendritic?

Dendritic is an architectural pattern for organizing NixOS, Home Manager, and
nix-darwin configurations where:

- Modules are organized by feature/concern rather than by type
- Each feature directory can ship `nixos.nix`, `home.nix`, and/or `darwin.nix`
- Flake wiring imports all feature modules automatically

**References:**
- [mightyiam/dendritic](https://github.com/mightyiam/dendritic)
- [Dendrix distribution](https://dendrix.oeiuwq.com/Dendritic.html)

## Current Layout (Adopted)

```
modules/
└── features/
    ├── base/
    │   ├── nixos.nix
    │   └── home.nix
    ├── desktop/
    │   ├── gnome/nixos.nix
    │   └── aerospace/home.nix
    ├── comin/nixos.nix
    ├── gaming/
    │   ├── nixos.nix
    │   └── icarus-mod-manager/home.nix
    ├── hardware/
    │   └── tuxedo/infinitybook-pro-16-gen8/nixos.nix
    └── ...
```

### Module Discovery

`flake.nix` uses `importTreeByName` to collect modules:

- `modules/features/**/nixos.nix` → NixOS modules
- `modules/features/**/home.nix` → Home Manager modules
- `modules/features/**/darwin.nix` → nix-darwin modules

## Conventions

1. **Feature directories** hold all config for a concern (service, profile, app).
2. **Guarded modules**: use `enable` options; hardware profiles default to `false`.
3. **Shared values** live next to the feature that uses them (no extra `specialArgs`).

## Why This Helps

- Less boilerplate in module lists
- Easier navigation by feature
- Consistent behavior across NixOS/Home Manager/Darwin
