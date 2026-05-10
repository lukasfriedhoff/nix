# Project Context

## Purpose

NixOS flake configuration managing personal workstations, homelab servers, and work systems with Home Manager integration. Provides declarative system and user configuration across Linux desktops, servers, and macOS.

## Tech Stack

- **Nix / NixOS** - Primary configuration language and OS
- **Flakes** - Reproducible builds with pinned dependencies
- **Home Manager** - User environment management
- **sops-nix** - Secrets management with Age encryption
- **comin** - Pull-based server auto-deployment
- **treefmt** - Code formatting (nixfmt, statix, deadnix)
- **nix-darwin** - macOS system configuration

## Project Structure

```
flake.nix              # Main flake definition with hosts and modules
lib/default.nix        # Custom library functions (importTreeByName, etc.)
modules/features/      # Feature modules with nixos.nix, home.nix, darwin.nix
hosts/                 # Host-specific configurations
  personal/            # Personal desktops (tux, tab, lenovo)
  work/                # Work machines (macbook-pro, docker-host)
  homelab/             # Server infrastructure (srv1, srv2, srv3)
resources/             # Static resources (SSH keys, Ceph topology)
secrets/profiles/      # SOPS-encrypted secrets by profile
pkgs/                  # Custom package overlays
scripts/               # Deployment and automation tools
```

## Code Conventions

### Commands

```bash
nix fmt                           # Format all Nix files
nix flake check --no-build        # Validate flake syntax
nix eval .#nixosConfigurations.<host>.config.system.build.toplevel --no-build
sudo nixos-rebuild switch --flake .#<hostname>
```

### Module Patterns

```nix
# Feature module structure
{ config, lib, ... }:
let cfg = config.<namespace>.<feature>;
in {
  options.<namespace>.<feature> = {
    enable = lib.mkEnableOption "<description>";
  };
  config = lib.mkIf cfg.enable { ... };
}
```

### Namespaces

- `profiles.*` - Base profile defaults
- `desktop.*` - Desktop environment features
- `lukasf.*` - Personal/infrastructure features
- `hardwareProfiles.*` - Hardware-specific configurations
- `programs.*` - Home Manager program options

### Git Workflow

- Main branch: `main`
- Development branch: `develop` (auto-deployed to servers via comin)
- Enable hooks: `git config core.hooksPath .githooks`

## Domain Context

### Profiles

| Profile | Type | User | Systems |
|---------|------|------|---------|
| tux, tab, lenovo | Personal Desktop | lukasf | GNOME workstations |
| srv1, srv2, srv3, srv4 | Homelab Server | lukasf | Ceph, k3s, LLM |
| mac | Work Desktop | lukasfriedhoff | macOS |
| docker-host-01 | Work Server | lukasf | Customer infrastructure |

### Secrets Routing

Secrets are routed via `specialArgs.secrets` with profile-based paths:
- `secrets.primary` - Host-specific secrets
- `secrets.shared` - Common across all profiles
- `secrets.profileShared` - Shared within profile group
- `secrets.ceph` - Ceph cluster secrets

## Constraints

- **Do NOT** run `nix build` on full configurations (use `nix eval` or `--no-build`)
- **NEVER** deploy directly - desktops are manual, servers auto-pull from `develop`
- **Always** run `nix fmt` before committing
- **Check** with `nix flake check --no-build` before pushing
