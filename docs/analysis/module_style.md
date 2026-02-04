# Module style guide

## Goals
- Keep module APIs predictable across services and profiles.
- Make it easy to enable/disable features and override defaults per host.
- Preserve sensible defaults while keeping host configs thin.

## Naming and layout
- `modules/nixos/services/<name>.nix` uses `lukasf.<name>` options.
- `modules/nixos/services/<group>/<name>.nix` uses `lukasf.<group>.<name>` options.
- `modules/nixos/profiles/desktop/<name>.nix` uses `desktop.<name>` options.
- `modules/nixos/profiles/homelab/<name>.nix` uses `homelab.<name>` options.
- `modules/nixos/profiles/dacoso/<name>.nix` uses `dacoso.<name>` options.
- `modules/nixos/profiles/base.nix` uses `profiles.base` options.
- `modules/nixos/profiles/server/comin.nix` keeps `lukasf.serverDeployment` (legacy name).

## Option patterns
- Always provide `enable` via `lib.mkEnableOption`.
  - Service modules usually default to `false`.
  - Profile modules that are always imported default to `true` using `// { default = true; }`.
- Use `package = lib.mkPackageOption pkgs "<pkg>" { };` when a module wraps a primary package.
- Use `openFirewall` (bool, default `false`) when a service binds to network ports.
- Provide `extraConfig` (`types.lines`) or `extraArgs` (`listOf str`) for pass-through configuration.
- For secret or path options, use `types.nullOr str`/`types.path` and describe how relative paths resolve.

## Implementation pattern
- Bind `cfg = config.<namespace>` and guard with `lib.mkIf cfg.enable`.
- Use `lib.mkDefault` in module config to keep host overrides easy.
- Use `lib.mkMerge` when combining unconditional defaults with optional blocks.
- Prefer `lib.getExe cfg.package` for executables.
- Add assertions when enabling requires extra inputs.

## Host overrides
- Enable modules in host config:
  ```nix
  desktop.gnome.enable = true;
  lukasf.nixCache.enable = true;
  ```
- Override module defaults with `lib.mkForce` when needed:
  ```nix
  services.resolved = lib.mkForce { enable = false; };
  ```
