# Nix Repo Agent Notes

## Workflow
- Run `nix fmt` (nixfmt) before committing any `.nix` changes.
- Prefer `./scripts/checks.sh` to validate formatting + `nix flake check`.
- If the git hook reformats files, re-stage the changes and re-run the commit.
- Build reusable modules first; use host-specific config only when it cannot be generalized.
- Use Conventional Commits for all commit messages.
- Git hooks live in `.githooks`: `git config core.hooksPath .githooks`.

## Module style (docs/analysis/module_style.md)
- Feature modules live under `modules/features/<feature>/`.
- Use `nixos.nix`, `home.nix`, and `darwin.nix` as entrypoints; the flake imports them via `importTreeByName`.
- Option namespaces:
  - Service/features: `lukasf.<feature>`
  - Desktop profiles: `desktop.<feature>`
  - Homelab profiles: `homelab.<feature>`
  - Dacoso profiles: `dacoso.<feature>`
  - Hardware profiles: `hardwareProfiles.<vendor>.<model>`
- Always provide `enable = lib.mkEnableOption` (profiles default to false unless intentionally global).
- Use `package = lib.mkPackageOption pkgs "<pkg>" { };` when wrapping a main package.
- Offer `openFirewall`, `extraConfig` (`types.lines`), or `extraArgs` (`listOf str`) where relevant.
- Guard with `lib.mkIf cfg.enable`, default with `lib.mkDefault`, and combine with `lib.mkMerge`.
- Prefer `lib.getExe cfg.package` for executables; add assertions when extra inputs are required.

## Secrets and sops (docs/architecture/secrets-routing.md, docs/analysis/secrets_map.md)
- Secrets are routed via `secretsByProfile` in `flake.nix` and passed as `specialArgs`.
- Use `secrets.primary/shared/profileShared/profileCommon/ceph` in host configs.
- `.sops.yaml` is the source of truth for recipients; update it and `docs/analysis/secrets_map.md` when adding a host.
- Age key locations: desktops `~/.config/sops/age/keys.txt`, servers `/var/lib/sops-nix/age/keys.txt`.
- Keep private IPs out of git; put real hostnames in `secrets/.../ssh/hostnames-private.conf`.

## Host onboarding (docs/deployment/personal-homelab.md, docs/deployment/remote-servers.md)
- Start from `hosts/homelab/template` or `scripts/homelab/new-host.sh`.
- Fetch hardware config with `scripts/homelab/probe-installer.sh`.
- Generate per-host management SSH keys with `scripts/servers/create-management-key.sh`.
- Add SSH key install entries to `resources/ssh/keys.nix` and hosts to `resources/ssh/hosts/personal.nix`.
- Add `secretsByProfile` and `nixosConfigurations` entries in `flake.nix`.
- Deploy with `scripts/servers/deploy-from-iso.sh` (nixos-anywhere wrapper).
- For initrd unlock, store the LUKS secret under `secrets/profiles/personal/shared/luks/<host>.txt`.

## WireGuard homelab (docs/networking/wireguard-homelab.md)
- Shared domain/endpoint live under `secrets/profiles/personal/shared/wireguard/`.
- Per-host keys live under `secrets/profiles/personal/desktops/<host>/wireguard/` or `.../servers/...`.

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
- Servers use comin in pull mode against `develop`.
- Flake uses `flake-parts` as-is; avoid deeper migration without a clear need.

## Further reading
- `README.md`
- `docs/analysis/module_style.md`
- `docs/analysis/flake-parts-eval.md`
- `docs/analysis/secrets_map.md`
- `docs/architecture/dendritic-pattern.md`
- `docs/architecture/secrets-routing.md`
- `docs/architecture/nixos-facter.md`
- `docs/deployment/personal-homelab.md`
- `docs/deployment/remote-servers.md`
- `docs/networking/wireguard-homelab.md`
- `docs/hardware/README.md`
- `docs/services/ceph.md`
