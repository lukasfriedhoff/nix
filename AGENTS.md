# Nix Repo Agent Notes

Single source of agent/contributor guidance for this repo. `CLAUDE.md` is a
one-line pointer to this file — put new guidance here, never there.

## Repository overview

A Nix monorepo managing personal workstations, homelab servers, and
customer-facing servers. NixOS flakes (with `flake-parts`) plus Home Manager,
nix-darwin, and SOPS for secrets.

## Repository map
- `flake.nix` is the source of truth for host outputs and `secretsByProfile`.
- Feature modules live under `modules/features/**` and are auto-imported via `myLib.importTreeByName`.
- Host-specific config lives under `hosts/**`; static SSH/infra data lives under `resources/**`; encrypted secrets live in the private `nix-secrets` repo (flake input), not in this repo.
- `nix/treefmt.nix` holds the formatter config (nixfmt, statix, deadnix); `nix/tests.nix` holds the integration tests.
- `lib/default.nix` holds the `myLib` helpers; `openspec/` holds the spec-driven change workflow.
- Keep host modules thin: default to reusable feature modules first, then host overrides only when needed.

## Commands

### Building and checking

```bash
# Preferred end-to-end validation (treefmt --fail-on-change + nix flake check).
# Optionally dry-runs a subset of hosts via NIX_CHECK_HOSTS="tux-h4xx-01 srv1".
./scripts/checks.sh

# Format only
nix fmt

# Validate flake syntax without building anything heavy
nix flake check --no-build

# Evaluate (do not build) a host configuration — prefer this over `nix build` of
# the full toplevel, which is expensive and rarely needed locally
nix eval .#nixosConfigurations.tux-h4xx-01.config.system.build.toplevel --no-build

# Build a specific host configuration (only when you actually need the closure)
nix build .#nixosConfigurations.tux-h4xx-01.config.system.build.toplevel

# Rebuild current NixOS system
sudo nixos-rebuild switch --flake .#<hostname>

# Rebuild macOS
darwin-rebuild switch --flake .#work-mbp-01

# Enter dev shell
nix develop

# Build a specific integration test (see `Tests` below for names)
nix build .#checks.x86_64-linux.pipewire-stack
```

When adding or modifying a feature module, also run a minimal runtime check
(build the affected package, launch the binary, or verify the unit starts) —
`nix flake check` validates evaluation but not behavior.

### Git hooks

Hooks live in `.githooks`; enable them with:

```bash
git config core.hooksPath .githooks
```

The pre-commit hook:
- Blocks raw OpenSSH private keys, and any staged `secrets/*` file without a sops payload
- Validates staged Nix files against the flake formatter (nixfmt + statix + deadnix)
- Runs a fast syntax guard over the staged Nix files only — a full `nix flake check --no-build` is deliberately *not* run here (too slow for a hook); use `./scripts/checks.sh` for that

If the hook reformats files, re-stage the changes and re-run the commit.

### CI/CD

- **Primary gate:** `.forgejo/workflows/ci.yml`, running on the in-cluster Forgejo runner, fires on push/PR. It runs the format check, evaluates hosts, then `promote`s by fast-forwarding `deploy`.
- **Break-glass twin:** `.github/workflows/ci.yml` is `workflow_dispatch`-only, for when the cluster hosting the Forgejo runner is itself broken (`gh workflow run CI --ref develop`). Keep its checks in step with the Forgejo workflow.
- Both need the `NIX_SECRETS_DEPLOY_KEY` secret (read-only deploy key on `nix-secrets`) to fetch the private flake input; the Forgejo job also needs `FORGEJO_TOKEN` (write:repository) to move `deploy`.

## Workflow
- Run `nix fmt` (nixfmt) before committing any `.nix` changes.
- Prefer `./scripts/checks.sh` to validate formatting + `nix flake check`.
- If `./scripts/checks.sh` reformats files (treefmt `--fail-on-change`), keep those changes, re-stage, and re-run the checks.
- Always run a minimal runtime test when adding or modifying a module (e.g., build the package, launch the binary, or verify the service starts).
- Build reusable modules first; use host-specific config only when it cannot be generalized.
- Use Conventional Commits for all commit messages.
- Non-trivial changes go through the spec-driven workflow in `openspec/` (`/openspec-proposal`, `/openspec-apply`, `/openspec-archive`); see `openspec/AGENTS.md` and `openspec/project.md`.

## Architecture

### Flake structure

`flake-parts` with imports from:
- `nix/treefmt.nix` — formatting configuration (nixfmt, statix, deadnix)
- `nix/tests.nix` — integration tests using `pkgs.testers.nixosTest`

Use `flake-parts` as-is; avoid deeper migration without a clear need.

### Module system

Features live in `modules/features/` with a naming convention:
- `nixos.nix` — NixOS module
- `home.nix` — Home Manager module
- `darwin.nix` — nix-darwin module

All matching files are auto-imported via `myLib.importTreeByName` in `flake.nix`
— no manual wiring needed.

**Option namespaces:**
- `lukasf.*` — personal NixOS features (pipewire, nixRegistry, shadowTech, …)
- `desktop.*` — desktop environments (gnome, plasma, laptop)
- `homelab.*` — homelab infrastructure (kubernetes, vlanBridges, longhornDisks, initrdSsh, ups)
- `work.*` — work server configuration
- `profiles.*` — profile enablement flags (desktop, server)
- `hardwareProfiles.<vendor>.<model>.*` — per-device hardware modules (e.g. `hardwareProfiles.tuxedo.infinitybook-pro-16-gen8`)
- `ai.*` — agent skill enablement (see *AI skills* below)
- `programs.*` — Home Manager programs (standard HM namespace)

### Host composition

Hosts are built from layered module sets defined in `flake.nix`:

```
coreModules              → Feature modules + sops-nix + comin + nixos-facter
├── baseDesktopModules   → + stylix + Home Manager
│   ├── gnomeDesktopModules  → + GNOME + laptop power management
│   ├── plasmaDesktopModules → + KDE Plasma
│   └── cloudDesktopModules  → + the Selkies cloud-desktop image
├── baseServerModules    → + server defaults + work server defaults
└── homelabServerModules → + server defaults (homelab personal servers only)
```

`mkHomelabHost <host>` wires `homelabServerModules` to
`hosts/homelab/<host>/configuration.nix`; `mkNixosHost <profile> <modules>` is
the general form. Darwin lives in `darwinConfigurations.work-mbp-01`.

### Special args available in modules

All modules receive these via `specialArgs`:
- `profile` — host profile identifier (e.g. `"tux"`, `"srv1"`, `"mac"`)
- `workSystem` — boolean, true for work profiles (affects SSH config, etc.)
- `repoRoot` — path to the repository root (`self`)
- `secrets` — attribute set with paths to encrypted secrets (see *Secrets and sops*)
- `inputs` — flake inputs
- `linuxUser` / `macUser` — username for the respective platform

### Library functions (`lib/default.nix`)

```nix
myLib.importTreeByName ./modules/features "nixos.nix"   # All files matching a name, recursively
myLib.resolveSecretPath { root = secrets.primary; path = "wireguard/key.txt"; }
myLib.resolveSecretFirst { roots = [ ... ]; path = "..."; }   # First root that has the file
```

### Profile system

Hosts are assigned profiles (`tux`, `tab`, `srv1`, `mac`, …) that determine:
- Secret paths via `secretsByProfile`
- Whether `workSystem = true` (affects SSH config)
- Default configuration values

## Module style (docs/analysis/module_style.md)
- Feature modules live under `modules/features/<feature>/`.
- Use `nixos.nix`, `home.nix`, and `darwin.nix` as entrypoints; the flake imports them via `importTreeByName`.
- Always provide `enable = lib.mkEnableOption` (profiles default to false unless intentionally global).
- Use `package = lib.mkPackageOption pkgs "<pkg>" { };` when wrapping a main package.
- Offer `openFirewall`, `extraConfig` (`types.lines`), or `extraArgs` (`listOf str`) where relevant.
- Guard with `lib.mkIf cfg.enable`, default with `lib.mkDefault`, and combine with `lib.mkMerge`.
- Prefer `lib.getExe cfg.package` for executables; add assertions when extra inputs are required.
- For host-specific patterns, consider creating shared base modules that can be reused rather than copying repeated configurations across hosts.

### Adding a new feature module

1. Create `modules/features/<name>/nixos.nix` (and/or `home.nix`, `darwin.nix`).
2. Follow the option pattern:
   ```nix
   { config, lib, pkgs, ... }:
   let cfg = config.<namespace>.<feature>;
   in {
     options.<namespace>.<feature> = {
       enable = lib.mkEnableOption "<description>";
       package = lib.mkPackageOption pkgs "<pkg>" { };
       openFirewall = lib.mkEnableOption "open service ports in the firewall";
       extraConfig = lib.mkOption {
         type = lib.types.lines;
         default = "";
       };
     };
     config = lib.mkIf cfg.enable {
       # Use lib.getExe cfg.package for executables
       # Use lib.mkDefault for values hosts may override
       # Combine multiple config blocks with lib.mkMerge
       # Add `assertions` when extra inputs are required
     };
   }
   ```
3. The module is auto-imported by `importTreeByName`.
4. Prefer reusable feature modules over host-specific config; only fall back to host overrides when the behavior genuinely cannot be generalized.
5. See `docs/analysis/module_style.md` for the full style guide.

## Secrets and sops (docs/architecture/secrets-routing.md, docs/analysis/secrets_map.md)
- Secrets live in the private repo github.com/lukasfriedhoff/nix-secrets, consumed as the `nix-secrets` flake input (git+ssh, `flake = false`). **This repo has no `secrets/` directory and no `.sops.yaml`.**
- Scripts resolve the local checkout via `NIX_SECRETS_DIR`, defaulting to `../nix-secrets` next to this repo (see `secrets_root()` in `scripts/lib/common.sh`).
- Secrets are routed via `secretsByProfile` in `flake.nix` and passed as `specialArgs`.
- Use `secrets.primary/shared/profileShared/profileCommon` in host configs:
  ```nix
  { secrets, ... }:
  {
    sops.secrets."wireguard-key" = {
      sopsFile = "${secrets.primary}/wireguard/key.priv";
      format = "binary";
    };
  }
  ```
- The `.sops.yaml` at the nix-secrets repo root is the source of truth for recipients; update it and `docs/analysis/secrets_map.md` when adding a host.
- Secrets layout roots (inside the nix-secrets repo):
  - `secrets/profiles/common/shared` for cross-profile shared material.
  - `secrets/profiles/personal/{desktops,servers,shared}` for personal scope.
  - `secrets/profiles/work/{desktops,servers,shared}` for work scope.
- Age key locations: desktops `~/.config/sops/age/keys.txt` (bootstrapped to `/var/lib/sops-nix/age/keys.txt`), servers `/var/lib/sops-nix/age/keys.txt`.
- Login password hashes come from sops: personal hosts share `secrets/profiles/personal/shared/login-password-hash.txt` (srv9 keeps a per-host copy); work servers consume `<server>/root-password-hash.txt` + `nixos-password-hash.txt` via `work.server` and need their age key in place before deploying. `hashedPasswordFile` is declarative — edit the secret and redeploy to rotate.
- Keep private IPs out of git; put real hostnames in the nix-secrets repo under `secrets/.../ssh/hostnames-private.conf`.
- Day-to-day sops usage (run inside the nix-secrets checkout):
  ```bash
  sops --encrypt --input-type binary plaintext.key > secrets/path/to/encrypted.key
  sops secrets/path/to/file.yaml      # edit in place
  sops -d secrets/path/to/file.key    # decrypt to stdout
  sops updatekeys secrets/path/to/file # re-encrypt after a recipient change
  ```

## Host onboarding (docs/deployment/personal-homelab.md, docs/deployment/remote-servers.md)
- Start from `hosts/homelab/template` or `scripts/homelab/new-host.sh`.
- Fetch hardware config with `scripts/homelab/probe-installer.sh`.
- Generate per-host management SSH keys with `scripts/servers/create-management-key.sh <host> <scope>`.
- Add SSH key install entries to `resources/ssh/keys.nix` and hosts to `resources/ssh/hosts/personal.nix`.
- For work hosts, maintain entries under `resources/ssh/hosts/work.nix`.
- Prefer `keyName = "<host>-<scope>-mgmt"` in SSH host entries so Home Manager expands to `~/.ssh/personal/<keyName>`.
- Add `secretsByProfile` and `nixosConfigurations` entries in `flake.nix`.
- Deploy with `scripts/servers/deploy-from-iso.sh` (nixos-anywhere wrapper).
- For local libvirt bootstrap runbooks (including srv3-style multi-disk VMs), start at `docs/deployment/qemu-vm-bootstrap.md`.
- Local VM bootstrap defaults:
  - Use `scripts/vms/new-qemu-vm.sh` with `--extra-disk` for swap/data disks.
  - Use `scripts/servers/deploy-from-iso.sh --identity <key> --luks-secret <secret>` (defaults to `disko,install,reboot` phases).
  - Use `scripts/homelab/unlock.sh <host>` for first post-install boot; if DNS is not ready, it now falls back to local libvirt lease IP automatically.
- During ISO install, copy the management `.pub` key to `/root/.ssh/authorized_keys` before deploy.
- After first boot, verify pull-mode updates with `systemctl status comin.service` and `journalctl -u comin.service`.
- For initrd unlock, store the LUKS secret in the nix-secrets repo under `secrets/profiles/personal/shared/luks/<host>.txt`.

### Adding a new homelab server

```bash
scripts/homelab/new-host.sh \
  --host srv8-k3s-stg4 \
  --fqdn srv8-k3s-stg4.example.com \
  --root-disk-id nvme-SAMSUNG_MZVL2512... \
  --ip 192.168.1.100 \
  --fs ext4 \
  --update-flake
```

This creates the host configuration under `hosts/homelab/<host>/`, a disko disk
layout with LUKS encryption, a per-host age key and management SSH key, the LUKS
passphrase in the nix-secrets repo, SSH config entries (access + initrd unlock),
and — with `--update-flake` — the `flake.nix` entries. Then deploy with
`scripts/servers/deploy-from-iso.sh <host> <installer-ip>`.

## WireGuard homelab (docs/networking/wireguard-homelab.md)
- Shared domain/endpoint live in the nix-secrets repo under `secrets/profiles/personal/shared/wireguard/`.
- Per-host keys live in the nix-secrets repo under `secrets/profiles/personal/desktops/<host>/wireguard/` or `.../servers/...`.

## Homelab and service modules
- `homelab.vlanBridges`: VLAN/bridge/systemd-networkd wiring; gateway data lives in `resources/homelab/networks.nix`.
- `homelab.longhornDisks`: LUKS unlock + mount of Longhorn data disks registered in `resources/homelab/disks.nix`.
- `homelab.bootstrapPassword`: applies a sops-backed bootstrap password to root/nixos.
- `homelab.kubernetes`: typed options only; the old `extraK3sFlags` escape hatch is gone. `homelab.kubernetes.gitops` bootstraps Flux against `flux-cluster` (the `repositories` Kustomization in flux-cluster then owns the GitRepository).
- `homelab.initrdSsh`: early-boot SSH for remote LUKS unlock.
- `lukasf.openWebui` is the single owner of `services.open-webui`; `lukasf.ollama` and `lukasf.llamaCpp` register as backends.
- `hosts/homelab/k3s-staging/node.nix` is the parameterized staging node (same pattern as `hosts/homelab/testingrke2/node.nix`).

Homelab servers additionally use **disko** (declarative LUKS-encrypted
partitioning), **initrd SSH**, **comin** (pull-mode deploys), and **k3s** with
FluxCD GitOps.

## AI skills
- External agent skills are vendored as flake inputs (fluxcd/agent-skills, anthropics/skills cherry-picks, michalzubkowicz/nixos-management-skill, foxj77/claude-code-skills) and linked via `modules/features/ai/home.nix`.
- Option paths follow `ai.skills.<dir-name>.enable` — one per directory under `modules/features/ai/skills/` plus one per vendored external skill (all enabled by default via `ai.enableAllSkills`).

## Hardware inventory (docs/hardware/README.md)
- Run `scripts/hardware-survey.sh` (and optionally `nixos-facter`).
- Add a module under `modules/features/hardware/<vendor>/<model>/nixos.nix`.
- Enable it in the host config with `hardwareProfiles.<vendor>.<model>.enable = true;`.
- Document the host in `docs/hardware/<host>.md`.

## nixos-facter (docs/architecture/nixos-facter.md)
- Store `facter.json` next to the host (`hosts/<scope>/<host>/facter.json`).
- The `lukasf.facter` module auto-wires `hardware.facter.reportPath` when a report exists.
- Override explicitly via `lukasf.facter.reportPath` if needed.

## Deployment model
- **Desktops:** manual `nixos-rebuild` / `darwin-rebuild`.
- **Servers:** comin in pull mode against the `deploy` branch. CI fast-forwards `deploy` from `develop` only after checks pass, so a broken eval never reaches a host. **Consequence: every push to `develop` reaches the production fleet automatically within ~30 minutes — treat `develop` as production and use feature branches for anything not ready to run on the servers.** (Learned 2026-08-25: the k3s HA migration deployed itself mid-outage-recovery.)
- Hosts never depend on in-homelab infrastructure to deploy: comin reads `https://codeberg.org/lukasfriedhoff/nix` with `https://github.com/lukasfriedhoff/nix` as fallback. Both are external push mirrors force-synced from the primary, Forgejo at `git.h4xx.io` — **push to Forgejo, never to a mirror.**
- **Fresh installs:** `scripts/servers/deploy-from-iso.sh` (nixos-anywhere wrapper).

## Tests

Integration tests are defined in `nix/tests.nix` using `pkgs.testers.nixosTest`:

```bash
nix flake check                                # runs all checks including tests
nix build .#checks.x86_64-linux.<test-name>    # one test
```

Current tests: `pipewire-stack`, `nix-gc-roots-cleaner`, `nix-registry`, and
(x86_64-linux only) `homelab-rke2-module`, `shadow-client-appimage`,
`icarus-mod-manager`, `selkies-desktop-image`. On aarch64-darwin, `nix flake
check` additionally evaluates `work-mbp-01-eval`.

Hosts can also define tests via the `integrationTests` option (exposed by
`flake.nixosModules.integrationTests` in `nix/tests.nix`). Any
`nixosConfiguration` that declares `integrationTests` has its entries merged
into `checks.x86_64-linux` automatically — per-host tests appear in `nix flake
check` without manual registration.

## Helper scripts

Lifecycle scripts live under `scripts/`. Most-used entry points:

| Script | Purpose |
|--------|---------|
| `scripts/checks.sh` | Repo-wide formatting + `nix flake check` (preferred local CI) |
| `scripts/homelab/new-host.sh` | Bootstrap new homelab host (config, secrets, keys, disko) |
| `scripts/homelab/probe-installer.sh` | Fetch hardware config and disk/NIC info from an installer ISO |
| `scripts/homelab/unlock.sh` | Remote LUKS unlock via initrd SSH (falls back to libvirt lease IP) |
| `scripts/homelab/remove-host.sh` | Tear a host back out of the flake, secrets and SSH config |
| `scripts/servers/deploy-from-iso.sh` | nixos-anywhere wrapper for fresh installs |
| `scripts/servers/create-management-key.sh` | Generate SSH keys and write SOPS-encrypted material |
| `scripts/vms/new-qemu-vm.sh` | Create a QEMU VM for local bootstrap testing (`--extra-disk` for swap/data) |

Others (`hardware-survey.sh`, `collect-power-metrics.sh`,
`scripts/personal/rebuild-with-cache.sh`, `scripts/matrix/*`,
`scripts/servers/setup-srv4-llm-runtime.sh`, …) are discoverable via
`ls scripts/**`.

## Documentation hygiene
- Prose documentation belongs in the second-brain vault, not in this repo's `docs/` tree, unless it is file-specific convention like the pages listed below.
- If secrets paths/recipients change, update both the nix-secrets repo's `.sops.yaml` and `docs/analysis/secrets_map.md`.
- If onboarding/deploy flow changes, update `docs/deployment/personal-homelab.md` and `docs/deployment/remote-servers.md`.
- If module conventions change, update `docs/analysis/module_style.md`.
- Keep `README.md` aligned with actual host inventory and helper scripts.
- Agent guidance goes in `AGENTS.md` (this file), never in `CLAUDE.md`.

## Further reading
- `README.md`
- `openspec/AGENTS.md`, `openspec/project.md`
- `docs/analysis/module_style.md`
- `docs/analysis/flake-parts-eval.md`
- `docs/analysis/secrets_map.md`
- `docs/architecture/dendritic-pattern.md`
- `docs/architecture/secrets-routing.md`
- `docs/architecture/nixos-facter.md`
- `docs/deployment/personal-homelab.md`
- `docs/deployment/remote-servers.md`
- `docs/deployment/qemu-vm-bootstrap.md`
- `docs/development/{module_development,host_onboarding,troubleshooting}.md`
- `docs/networking/wireguard-homelab.md`
- `docs/services/` (backup, local-llm, matrix-migration, media-stack, video-gen, …)
- `docs/hardware/README.md`
