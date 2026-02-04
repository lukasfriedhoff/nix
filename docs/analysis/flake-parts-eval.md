# Flake-parts evaluation (step 8)

## Status
- Decision: keep the current flake-parts usage as-is (no migration).
- Rationale: the repo already uses `flake-parts` in `flake.nix`, and the remaining pain points are not solved by a deeper rewrite.

## Current usage
- `flake.nix` is built with `flake-parts.lib.mkFlake`.
- `perSystem` is used for formatter/devshell.
- Outputs (`nixosConfigurations`, `darwinConfigurations`, `homeConfigurations`) are built in the `flake` section with local helpers.

## What "full adoption" would mean here
- Move large `let` blocks (host lists, `secretsByProfile`, module stacks) into flake-parts modules or `imports`.
- Split outputs into smaller flake-parts modules (e.g., `nixosConfigurations` in its own module).
- Reduce ad-hoc `specialArgs` glue in favor of flake-parts module arguments where possible.

## Pros of deeper adoption
- Clearer separation of concerns inside `flake.nix`.
- Easier reuse of shared values across outputs.
- Better scaling if more systems/outputs are added.

## Cons / risks
- Non-trivial refactor for limited upside.
- Increased indirection can make debugging harder for small changes.
- Current layout already works and is documented (see `docs/architecture/dendritic-pattern.md`).

## Decision and follow-ups
- No further flake-parts migration in this refactor.
- Revisit only if:
  - host count or output complexity grows significantly, or
  - shared data (`secretsByProfile`, host lists) becomes hard to maintain.
