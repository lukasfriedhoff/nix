# Design — Work Employer Separation

## Decision 1: Employer is a data axis, not an option namespace

The previous employer leaked in as a `dacoso.*` option namespace, which had to be renamed to
`work.*` later. To avoid repeating that, employer is modelled as **data**:

- a path segment (`work/<employer>/…`),
- a `specialArgs.employer` string (nullable for non-work hosts),
- a `work.employer` option whose default comes from that specialArg.

Employer-specific behavior is expressed as `lib.mkIf (config.work.employer == "group24") { … }`
inside the existing `work` modules — never as a new top-level namespace. Adding an employer is
then: create the path, add one `employerByProfile` entry, (optionally) add `mkIf` branches.

## Decision 2: Path shape

```
hosts/work/<employer>/{desktops,servers}/<host>/
secrets/profiles/work/<employer>/{desktops,servers}/<host>/   # in nix-secrets
```

`<employer>` is lowercase, no spaces (`group24`). The `{desktops,servers}` split is retained
under each employer. `work/shared/` (currently `workSharedRoot`) stays employer-agnostic for
cross-employer shared material, OR moves under employer if nothing is truly cross-employer —
resolved during apply by inspecting what `workSharedRoot` holds.

## Decision 3: flake.nix routing

```nix
employerByProfile = {
  mac = "group24";
  # future: <profile> = "<employer>";
};
workEmployerFor = profile: employerByProfile.${profile} or null;

# per-profile work secrets root, now employer-scoped
mkWorkSecrets = employer: host:
  let root = "${workProfileRoot}/${employer}/${host}"; in { ... };

# specialArgs gains employer (null for personal/homelab)
mkSpecialArgs = profile: { ...; employer = workEmployerFor profile; };
```

`secretsByProfile.mac` becomes
`mkWorkSecrets "group24" "desktops/work-mbp-01"` (exact arg shape finalized against the
current `mkWorkSecrets` signature during apply).

## Decision 4: SSH layout

Options considered:
- (A) keep one `resources/ssh/hosts/work.nix`, group entries by employer with comments.
- (B) split into `resources/ssh/hosts/work/<employer>.nix` and import per employer.

**Chosen: (A) for now** — only one employer host (the Mac) exists after removal, so a split is
premature. Revisit to (B) when a second employer gains SSH hosts. Old-host entries (if any)
are removed regardless.

## Decision 5: Removal vs. the previous employer's `work.server` defaults

Removing `docker-host-01` + `timebutler-test-vm` does not touch the generic `work.server`
module (it stays; the Mac and future employer servers use it). No employer currently needs
custom `work.server` defaults, so `work.employer` is wired but drives nothing yet — that's
intentional (the hook is the deliverable, not speculative config).

## Cross-repo sequencing (critical)

1. In `nix-secrets`: `git mv` the Mac's secret dir to the new employer path; `sops updatekeys`
   moved files; delete the two old server dirs; update `.sops.yaml` creation rules; commit +
   push `nix-secrets` **first**.
2. In `nix`: apply flake/host/module/doc changes; `nix eval` the Mac + a personal host + a
   homelab host to prove nothing regressed; only then commit.
3. Never push the `nix` change ahead of the `nix-secrets` change, or the Mac loses its secrets.

## Open questions for apply

- Exact current `mkWorkSecrets` signature (positional vs attr) — read before editing.
- Whether `.sops.yaml` has any per-host rule for the two removed hosts (grep found none by
  name; confirm it is purely path-glob).
- Contents of `workSharedRoot` — decides whether `shared/` stays top-level or moves.
