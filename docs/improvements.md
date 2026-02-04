# Changelog

## Refactor milestone (monorepo cleanup)
- Restructured hosts into `hosts/personal`, `hosts/homelab`, `hosts/work` and moved macOS modules into `modules/darwin`.
- Normalized naming and templates (`disko.nix`, `hosts/homelab/template`).
- Wired `myLib` helpers into `flake.nix` and refactored module stacks into reusable layers (`coreModules`, `desktopExtras`, `serverExtras`).
- Reduced hardcoded values in modules by turning them into options (Linux user, NVIDIA bus ID).
- Added Home Manager modules for Moonlight, AeroSpace, and SketchyBar with default configs.
- Documented secrets layout, module composition, and deployment flows in `docs/analysis` and `docs/architecture`.

## Verification
- `nix fmt --check .`
- `nix flake check`
