# Implementation Tasks

## Phase 0: Pre-flight (read before editing)
- [ ] Read current `mkWorkSecrets` / `workProfileRoot` / `workSharedRoot` / `mkSpecialArgs` in `flake.nix`
- [ ] Confirm `../nix-secrets/.sops.yaml` work rules are path-glob (no per-host recipient for the two removed hosts)
- [ ] Inspect `workSharedRoot` contents to decide if `shared/` stays employer-agnostic
- [ ] Note the Mac's current Age recipient(s) so the moved secret still decrypts

## Phase 1: nix-secrets (private repo, push FIRST)
- [ ] `git mv secrets/profiles/work/desktops/work-mbp-01 secrets/profiles/work/group24/desktops/work-mbp-01`
- [ ] Update `.sops.yaml` creation rules to the `work/<employer>/…` layout
- [ ] `sops updatekeys` on the moved file(s); verify decrypt with the Mac key
- [ ] `git rm -r secrets/profiles/work/servers/docker-host-01 secrets/profiles/work/servers/timebutler-test-vm`
- [ ] Commit + push nix-secrets to Forgejo primary

## Phase 2: Employer axis in flake.nix
- [ ] Add `employerByProfile = { mac = "group24"; }` and `workEmployerFor`
- [ ] Reshape `mkWorkSecrets` to take an employer segment; repoint `secretsByProfile.mac` to `work/group24/desktops/work-mbp-01`
- [ ] Add `employer` to `mkSpecialArgs` (null for non-work profiles)

## Phase 3: work module
- [ ] Add `work.employer` option (default from `specialArgs.employer`) in `modules/features/work/` (new shared options file or `work/server/nixos.nix`)
- [ ] Leave employer-specific defaults empty (hook only) — no `group24` config yet

## Phase 4: Host moves + removals
- [ ] `git mv hosts/work/work-mbp-01 hosts/work/group24/desktops/work-mbp-01`; fix the path in `darwinConfigurations.work-mbp-01`
- [ ] `git rm -r hosts/work/docker-host-01 hosts/work/timebutler-test-vm`
- [ ] Remove `docker-host-01` + `timebutler-test-vm` from `secretsByProfile`, `workProfiles`, and `nixosConfigurations` in `flake.nix`
- [ ] Remove any `resources/ssh/hosts/work.nix` entries for the two hosts; group remaining entries by employer

## Phase 5: Docs
- [ ] Replace stale `dacoso` references in `docs/deployment/remote-servers.md`, `manualToDo.md`, and any others with employer-aware wording
- [ ] Note the `work/<employer>/…` layout + `work.employer` in the relevant doc/AGENTS

## Verification
- [ ] `nix fmt`
- [ ] `nix flake check --no-build`
- [ ] `nix eval .#darwinConfigurations.work-mbp-01.config.system.build.toplevel.drvPath` (Mac still evaluates, new secret path)
- [ ] `nix eval .#nixosConfigurations.tux-h4xx-01.config.system.build.toplevel.drvPath` (personal host unaffected)
- [ ] `nix eval .#nixosConfigurations.srv1.config.system.build.toplevel.drvPath` (homelab host unaffected)
- [ ] Confirm the two removed hosts no longer appear in `nix flake show`
- [ ] Push order respected: nix-secrets pushed before the nix repo change
