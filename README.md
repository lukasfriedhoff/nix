## Lukas Friedhoff's Nix monorepo

This flake drives personal workstations, homelab machines, and a couple of
customer-facing servers.

## Repository Structure

```
.
├── flake.nix              # Main entry point - all host definitions
├── flake.lock             # Pinned dependency versions
├── lib/                   # Custom library functions
│   └── default.nix        # Import helpers (importDir, importSubdirs, importTree)
├── modules/nixos/         # Reusable NixOS modules
│   ├── profiles/          # Role-based configs (desktop, server, homelab)
│   │   └── desktop/
│   │       ├── gnome.nix
│   │       ├── plasma.nix
│   │       ├── laptop.nix # Power management for mobile devices
│   │       └── gaming.nix
│   ├── services/          # System services (ceph, kvm, wireguard)
│   └── hardware/          # Device-specific configs
├── home/                  # Home Manager configuration
│   ├── programs/          # User programs (organized by category)
│   │   ├── dev/           # Development: git, neovim, vscode
│   │   ├── devops/        # Infrastructure: kubectl, k9s, velero
│   │   ├── utils/         # Utilities: alacritty, starship, gpg
│   │   ├── work/          # Work tools: cassandra, mariadb, maven
│   │   └── gaming/        # Gaming: mod managers
│   └── platforms/         # OS-specific config (linux, macos)
├── hosts/                 # Host-specific configurations
├── resources/             # Static resources (SSH hosts, Ceph topology)
├── secrets/               # SOPS-encrypted secrets (by profile)
├── scripts/               # Automation tools
└── docs/                  # Documentation
    ├── architecture/      # Architecture decisions
    ├── hardware/          # Hardware inventory and quirks
    ├── services/          # Service documentation
    └── deployment/        # Deployment guides
```

## Key Entry Points

- `flake.nix` – declarative host definitions (`nixosConfigurations.*`,
  `darwinConfigurations.*`, `homeConfigurations.*`)
- `modules/` – reusable NixOS/Home Manager profiles (desktops, servers, secrets)
- `home/` – user-level Home Manager configuration
- `hosts/` – host-specific modules and hardware descriptors
- `scripts/` – helper tooling (bootstrap keys, deploy remote hosts, etc.)
- `docs/` – long-form documentation

## Managed Hosts

| Host | Type | Profile | Description |
|------|------|---------|-------------|
| tux-h4xx-01 | Desktop | GNOME | TUXEDO InfinityBook Pro 16 Gen8 (gaming) |
| tab-h4xx-02 | Desktop | GNOME | ASUS Vivobook T3300 (tablet) |
| srv4-vm-01 | Desktop | Plasma | Virtual machine |
| srv1 | Server | Homelab | Personal homelab (Ceph, k3s) |
| macbook-pro | Darwin | macOS | Work MacBook |
| docker-host-01 | Server | Work | Customer Docker host |

## Features

### System Management
- **Automatic garbage collection**: Weekly cleanup of old generations (30+ days)
- **Store optimization**: Automatic deduplication via hard links
- **Power management**: Laptop profile with auto-cpufreq, thermald, TLP support

### Services
- **Ceph**: Distributed storage with encrypted OSD support
- **Kubernetes**: k3s with FluxCD GitOps
- **WireGuard**: Homelab mesh VPN
- **Remote builders**: Distributed Nix builds

### Secrets
- **SOPS + Age**: Per-host encryption keys
- **Automatic backups**: Encrypted Ceph key backups
- **Pre-commit hooks**: Block unencrypted secrets

## Git Hooks

This repo provides a pre-commit hook that:
1. Blocks committing unencrypted secrets or raw private keys
2. Validates Nix formatting via nixfmt-tree
3. Runs `nix flake check` for syntax validation

Enable it locally:

```bash
git config core.hooksPath .githooks
```

### Deployment model

- Desktops are upgraded manually with `nixos-rebuild` / `darwin-rebuild`.
- Servers now ship with [comin](https://github.com/nlewo/comin) in pull mode:
  every host polls `https://github.com/lukasfriedhoff/nix` (branch `develop`)
  and applies the matching `nixosConfigurations.<hostname>` generation.
- Fresh installs / rebuilds from a NixOS ISO are orchestrated via
  `scripts/servers/deploy-from-iso.sh`, a thin wrapper around
  [`nixos-anywhere`](https://github.com/nix-community/nixos-anywhere).

### CI/CD

`.github/workflows/ci.yml` runs `nix fmt` and `nix flake check` for pushes and
pull requests against the long-lived branches. This keeps formatting + eval
errors out of `develop`.

### SSH + secrets

SSH hosts and identities are consolidated under `resources/ssh/hosts.nix` (which
imports `resources/ssh/hosts/personal.nix` and `resources/ssh/hosts/dacoso.nix`) and
consumed by Home Manager. Keys are created through
`scripts/servers/create-management-key.sh`, which also writes the SOPS-encrypted
material into the correct secret directories.

## Documentation

| Topic | Location |
|-------|----------|
| Hardware inventory | [`docs/hardware/`](docs/hardware/) |
| Ceph module | [`docs/services/ceph.md`](docs/services/ceph.md) |
| Backup procedures | [`docs/services/backup.md`](docs/services/backup.md) |
| Remote deployment | [`docs/deployment/remote-servers.md`](docs/deployment/remote-servers.md) |
| Architecture decisions | [`docs/architecture/`](docs/architecture/) |

### Architecture Documents

- [Secrets routing](docs/architecture/secrets-routing.md) - How secrets are routed to hosts
- [nixos-facter evaluation](docs/architecture/nixos-facter.md) - Hardware detection tool assessment
- [Dendritic pattern](docs/architecture/dendritic-pattern.md) - Module organization pattern analysis

## Helper Scripts

- `scripts/hardware-survey.sh` - Collect hardware inventory for troubleshooting
- `scripts/collect-power-metrics.sh` - Battery/power diagnostics for laptops
- `scripts/servers/deploy-from-iso.sh` - nixos-anywhere wrapper for fresh installs
- `scripts/servers/create-management-key.sh` - Generate SSH keys with SOPS encryption

### Related Projects

- [`mrVanDalo/nixos-artifacts-agenix`](https://github.com/mrVanDalo/nixos-artifacts-agenix)
  adds an agenix backend to the `nixos-artifacts` framework (serialize, encrypt,
  and distribute build artifacts). It is a practical reference for wiring agenix
  into custom flake outputs and can be reused for future binary/artifact
  distribution needs.

## Need Help?

Open an issue in this repository or poke me on Matrix if you discover a missing
edge-case or want to extend the scripts.
