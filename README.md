## Lukas Friedhoff's Nix monorepo

This flake drives personal workstations, homelab machines, and a couple of
customer-facing servers. The important entry points are:

- `flake.nix` – declarative host definitions (`nixosConfigurations.*`,
  `darwinConfigurations.*`, `homeConfigurations.*`)
- `modules/` – reusable NixOS/Home Manager profiles (desktops, servers, secrets)
- `home/` – user-level Home Manager configuration
- `hosts/` – host-specific modules and hardware descriptors
- `scripts/` – helper tooling (bootstrap keys, deploy remote hosts, etc.)
- `docs/` – long-form documentation (see especially
  [`docs/deployment/remote-servers.md`](docs/deployment/remote-servers.md))

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

SSH hosts and identities are consolidated under `resources/ssh/hosts.nix` and
consumed by Home Manager. Keys are created through
`scripts/servers/create-management-key.sh`, which also writes the SOPS-encrypted
material into the correct secret directories.

### Related projects

- [`mrVanDalo/nixos-artifacts-agenix`](https://github.com/mrVanDalo/nixos-artifacts-agenix)
  adds an agenix backend to the `nixos-artifacts` framework (serialize, encrypt,
  and distribute build artifacts). It is a practical reference for wiring agenix
  into custom flake outputs and can be reused for future binary/artifact
  distribution needs.

### Need help?

Open an issue in this repository or poke me on Matrix if you discover a missing
edge-case or want to extend the scripts.
