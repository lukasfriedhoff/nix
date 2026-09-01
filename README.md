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
├── modules/               # Feature-based modules (NixOS, Home Manager, Darwin)
│   └── features/
│       ├── base/          # Base defaults (nixos.nix, home.nix)
│       ├── desktop/       # Desktop profiles + desktop apps
│       ├── gaming/        # Gaming stack (system + home)
│       ├── homelab/       # Homelab profiles (k3s, longhorn disks, vlan bridges)
│       ├── hardware/      # Device-specific profiles
│       └── ...
├── hosts/                 # Host-specific configurations
├── resources/             # Static resources (SSH hosts, homelab disks/networks)
├── scripts/               # Automation tools
└── docs/                  # Documentation
    ├── architecture/      # Architecture decisions
    ├── hardware/          # Hardware inventory and quirks
    ├── services/          # Service documentation
    └── deployment/        # Deployment guides
```

SOPS-encrypted secrets live in the private repo
[`lukasfriedhoff/nix-secrets`](https://github.com/lukasfriedhoff/nix-secrets),
consumed as the `nix-secrets` flake input (git+ssh, `flake = false`). Scripts
find the local checkout via `NIX_SECRETS_DIR` (default: `../nix-secrets` next
to this repo).

## Key Entry Points

- `flake.nix` – declarative host definitions (`nixosConfigurations.*`,
  `darwinConfigurations.*`, `homeConfigurations.*`)
- `modules/` – feature-based NixOS/Home Manager/Darwin modules (`modules/features`)
- `hosts/` – host-specific modules and hardware descriptors
- `scripts/` – helper tooling (bootstrap keys, deploy remote hosts, etc.)
- `docs/` – long-form documentation

## Managed Hosts

| Host | Type | Profile | Description |
|------|------|---------|-------------|
| tux-h4xx-01 | Desktop | GNOME | TUXEDO InfinityBook Pro 16 Gen8 (gaming) |
| tab-h4xx-02 | Desktop | GNOME | ASUS Vivobook T3300 (tablet) |
| lenovo-h4xx-03 | Desktop | GNOME | Lenovo ThinkPad P15 Gen 2i |
| srv4-vm-01 | Desktop | Plasma | Virtual machine |
| virtual-05 | Desktop | GNOME | Virtual desktop (Moonlight target) |
| virtual-05-container | Desktop | GNOME | Container image of virtual-05 |
| srv1 | Server | Homelab | Personal homelab (k3s) |
| srv2 | Server | Homelab | Personal homelab node |
| srv3 | Server | Homelab | Personal homelab node |
| srv8 | Server | Homelab | Production Kubernetes node |
| srv9 | Server | Homelab | Production Kubernetes node |
| srv5-k3s-stg1 | Server | Homelab | Staging cluster node 1 |
| srv6-k3s-stg2 | Server | Homelab | Staging cluster node 2 |
| srv7-k3s-stg3 | Server | Homelab | Staging cluster node 3 |
| testingrke2-01 | Server VM | Homelab | Local RKE2 migration lab control-plane node 1 |
| testingrke2-02 | Server VM | Homelab | Local RKE2 migration lab control-plane node 2 |
| testingrke2-03 | Server VM | Homelab | Local RKE2 migration lab control-plane node 3 |
| work-mbp-01 | Darwin | macOS | Group24 work MacBook |
| docker-host-01 | Server | Work | Customer Docker host |
| lf-timebutler-testvm-01 | Server | Work | Timebutler test VM |

## Features

### System Management
- **Automatic garbage collection**: Weekly cleanup of old generations (30+ days)
- **Store optimization**: Automatic deduplication via hard links
- **Power management**: Laptop profile with auto-cpufreq, thermald, TLP support

### Services
- **Kubernetes**: reusable k3s/RKE2 nodes with FluxCD GitOps
- **WireGuard**: Homelab mesh VPN
- **Remote builders**: Distributed Nix builds
  - Runbook: `docs/deployment/remote-builders.md`

### Secrets
- **SOPS + Age**: Per-host encryption keys
- **Private nix-secrets repo**: encrypted material lives out of tree, pulled in as a flake input
- **Pre-commit hooks**: Block unencrypted secrets

## Git Hooks

This repo provides a pre-commit hook that:
1. Blocks committing unencrypted secrets or raw private keys
2. Validates Nix formatting via `nix fmt` (treefmt with nixfmt + statix + deadnix, configured in `nix/treefmt.nix`)
3. Runs `nix flake check` for syntax validation

Enable it locally:

```bash
git config core.hooksPath .githooks
```

### Deployment model

- Desktops are upgraded manually with `nixos-rebuild` / `darwin-rebuild`.
- Servers now ship with [comin](https://github.com/nlewo/comin) in pull mode:
  every host polls `https://github.com/lukasfriedhoff/nix` (branch `deploy`)
  and applies the matching `nixosConfigurations.<hostname>` generation. CI
  fast-forwards `deploy` from `develop` only after checks pass, so a broken
  eval never reaches a host.
- Fresh installs / rebuilds from a NixOS ISO are orchestrated via
  `scripts/servers/deploy-from-iso.sh`, a thin wrapper around
  [`nixos-anywhere`](https://github.com/nix-community/nixos-anywhere).

### CI/CD

`.github/workflows/ci.yml` runs `nix fmt` and `nix flake check --no-build` for
pushes and pull requests against the long-lived branches. The checks job needs
the `NIX_SECRETS_DEPLOY_KEY` repository secret (a read-only deploy key on
nix-secrets) to fetch the private flake input. On green pushes to `develop`,
the promote job fast-forwards the `deploy` branch that comin tracks.

### SSH + secrets

SSH hosts and identities are consolidated under `resources/ssh/hosts.nix` (which
imports `resources/ssh/hosts/personal.nix` and `resources/ssh/hosts/work.nix`) and
consumed by Home Manager. Keys are created through
`scripts/servers/create-management-key.sh`, which also writes the SOPS-encrypted
material into the correct directories of the local nix-secrets checkout.

## Documentation

| Topic | Location |
|-----|----------|
| Hardware inventory | [`docs/hardware/`](docs/hardware/) |
| Backup procedures | [`docs/services/backup.md`](docs/services/backup.md) |
| Remote deployment | [`docs/deployment/remote-servers.md`](docs/deployment/remote-servers.md) |
| srv4 LLM runtime (RHEL) | [`docs/deployment/srv4-llm-runtime.md`](docs/deployment/srv4-llm-runtime.md) |
| QEMU VM bootstrap | [`docs/deployment/qemu-vm-bootstrap.md`](docs/deployment/qemu-vm-bootstrap.md) |
| Testing RKE2 VM lab | [`docs/deployment/testingrke2-lab.md`](docs/deployment/testingrke2-lab.md) |
| Architecture decisions | [`docs/architecture/`](docs/architecture/) |
| Module development | [`docs/development/module_development.md`](docs/development/module_development.md) |
| Host onboarding | [`docs/development/host_onboarding.md`](docs/development/host_onboarding.md) |

### Architecture Documents

- [Secrets routing](docs/architecture/secrets-routing.md) - How secrets are routed to hosts
- [nixos-facter evaluation](docs/architecture/nixos-facter.md) - Hardware detection tool assessment
- [Dendritic pattern](docs/architecture/dendritic-pattern.md) - Module organization pattern analysis

## Helper Scripts

- `scripts/hardware-survey.sh` - Collect hardware inventory for troubleshooting
- `scripts/collect-power-metrics.sh` - Battery/power diagnostics for laptops
- `scripts/servers/deploy-from-iso.sh` - nixos-anywhere wrapper for fresh installs
- `scripts/servers/create-management-key.sh` - Generate SSH keys with SOPS encryption
- `scripts/servers/setup-srv4-llm-runtime.sh` - Configure llama.cpp + Open WebUI on RHEL srv4 via podman/systemd
- `scripts/homelab/probe-installer.sh` - Fetch hardware config and disk/NIC info from installer ISO
- `scripts/homelab/add-testing-resources.sh` - Add testing resources to the homelab cluster

### Related Projects

- [`mrVanDalo/nixos-artifacts-agenix`](https://github.com/mrVanDalo/nixos-artifacts-agenix)
  adds an agenix backend to the `nixos-artifacts` framework (serialize, encrypt,
  and distribute build artifacts). It is a practical reference for wiring agenix
  into custom flake outputs and can be reused for future binary/artifact
  distribution needs.

## Need Help?

Open an issue in this repository or poke me on Matrix if you discover a missing
edge-case or want to extend the scripts.
