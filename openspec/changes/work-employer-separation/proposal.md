# Work Employer Separation

## Problem Statement

The `work` profile structure is flat and single-tenant: one `hosts/work/{desktops,servers}/`
tree, one `secrets/profiles/work/{desktops,servers}/` tree, one `workProfiles` list, and a
single `work.server` module. It carries no notion of *which employer* a machine belongs to.

The owner changed employers — now at **group24** — and the previous employer's machines
(`docker-host-01`, `timebutler-test-vm`) are still defined. Without an employer dimension,
group24 hosts and any future employer's hosts collide in the same namespace, secret paths,
SSH config, and module defaults, with no way to apply employer-specific configuration
(proxies, CA bundles, VPN, tooling) or to cleanly retire an employer.

Note: the codebase already migrated off the previous employer's `dacoso.*` option namespace
to the generic `work.server` module and `resources/ssh/hosts/work.nix`; only documentation
still references "dacoso". This change does not reintroduce employer names as option
namespaces — employer is a *data* axis (path + specialArg + option value), not new modules.

## Goals

- Introduce an **employer axis** so `work/<employer>/…` cleanly separates machines, secrets,
  and SSH config per employer, with room for future employers added by data, not refactor.
- Surface the employer to modules as `specialArgs.employer` (via an `employerByProfile` map)
  and a `work.employer` option, so employer-specific defaults can key off it.
- Migrate the work MacBook **`work-mbp-01` to group24** as group24's first host, including its
  secrets path.
- **Remove the previous employer's hosts** `docker-host-01` and `timebutler-test-vm` entirely
  (public repo + private `nix-secrets`), deleting from the tree (git history retains them).
- Refresh stale docs that still say "dacoso" to the generic/employer-aware wording.
- Preserve the invariant that `develop` is production: every affected `nixosConfiguration` /
  `darwinConfiguration` must still evaluate after the change.

## Approach

**Employer as a data axis, not a module namespace.**

1. **Paths** — reshape work trees from `work/{desktops,servers}/<host>` to
   `work/<employer>/{desktops,servers}/<host>` in both `hosts/work/` and
   `nix-secrets` `secrets/profiles/work/`.
2. **Routing** — in `flake.nix`, add `employerByProfile = { mac = "group24"; }` (extend per
   host). `workProfileRoot` gains an `<employer>` segment resolved per profile; `mkWorkSecrets`
   takes the employer-scoped root. `mkSpecialArgs` passes `employer` (nullable; non-work hosts
   get `null`).
3. **Module** — `modules/features/work/server` (and a small shared `work` options module) gains
   `work.employer` (enum/str, default from `specialArgs.employer`). Employer-specific defaults
   live behind `lib.mkIf (cfg.employer == "group24")` as they arise — none are introduced in
   this change beyond wiring the option.
4. **SSH** — keep `resources/ssh/hosts/work.nix`, but structure its entries so employer is
   evident (e.g. a per-employer section or `work/<employer>.nix` split — decided in design.md).
5. **Removal** — delete the two old hosts' `nixosConfigurations`, `secretsByProfile` and
   `workProfiles` entries, `hosts/work/<host>/` dirs, SSH entries, and their
   `nix-secrets/secrets/profiles/work/servers/<host>/` dirs. Verify `.sops.yaml` rules are
   path-glob (no per-host recipient to prune); adjust only if a per-host rule exists.

## Files Affected

Public `nix` repo:
- `flake.nix` — `employerByProfile` (new), `workProfileRoot`/`mkWorkSecrets` reshape,
  `mkSpecialArgs` (`employer`), remove `docker-host-01` + `timebutler-test-vm` from
  `secretsByProfile`/`workProfiles`/`nixosConfigurations`, repoint `mac` to `work/group24`.
- `hosts/work/` — move `work-mbp-01` under `work/group24/desktops/`; delete
  `hosts/work/docker-host-01/`, `hosts/work/timebutler-test-vm/`.
- `modules/features/work/server/nixos.nix` (+ possibly a new `modules/features/work/options`)
  — add `work.employer`.
- `resources/ssh/hosts/work.nix` — employer structure; drop old-host entries if present.
- Docs: `docs/deployment/remote-servers.md`, `manualToDo.md`, any others referencing `dacoso`.

Private `nix-secrets` repo:
- Move `secrets/profiles/work/desktops/work-mbp-01` → `work/group24/desktops/work-mbp-01`.
- Delete `secrets/profiles/work/servers/{docker-host-01,timebutler-test-vm}/`.
- `.sops.yaml` — re-path creation rules for the `work/<employer>/…` layout; verify/prune.

## Risks & Considerations

- **Production fleet:** `work-mbp-01` is a live machine; its secret path move must land in
  `nix-secrets` and `flake.nix` atomically or the next `darwin-rebuild` breaks. Sequence the
  secrets move + sops re-key before/with the flake change; verify eval before any push.
- **sops re-encryption:** moving a secret path can change which creation rule applies; run
  `sops updatekeys` on moved files and confirm the Mac's Age recipient still decrypts.
- **Cross-repo atomicity:** public `nix` and private `nix-secrets` change together; document
  the push order (secrets first) in tasks.
- **No new employer modules:** keep employer as data; resist creating a `group24.*` namespace
  (the `dacoso.*` lesson). `work.employer` + `mkIf` is the pattern.
- **Reversibility:** deletions are git-recoverable; the Mac migration is the only
  state-sensitive step.
