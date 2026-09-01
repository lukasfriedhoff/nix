# Module style guide

## Goals
- Keep module APIs predictable across services and profiles.
- Make it easy to enable/disable features and override defaults per host.
- Preserve sensible defaults while keeping host configs thin.

## Naming and layout
- Feature modules live under `modules/features/<feature>/`.
- Use `nixos.nix`, `home.nix`, and `darwin.nix` to scope config to each system.
- Group related features in subdirectories (e.g., `desktop/`, `homelab/`, `devops/`).
- Option namespaces:
  - Service/features: `lukasf.<feature>`
  - Desktop profiles: `desktop.<feature>`
  - Homelab profiles: `homelab.<feature>`
  - Work profiles: `work.<feature>`
  - Base defaults: `profiles.base`
  - Hardware profiles: `hardwareProfiles.<vendor>.<model>`

## Option patterns
- Always provide `enable` via `lib.mkEnableOption`.
  - Service modules usually default to `false`.
- Profile modules that should apply globally can default to `true`; feature profiles should default to `false` and be enabled in the flake or host config.
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
