---
name: nix
description: NixOS and Nix flake development patterns
globs:
  - "**/*.nix"
  - "flake.nix"
  - "flake.lock"
---

# Nix Monorepo Skill

This is a NixOS configuration monorepo using flakes.

## Structure

- `flake.nix` - Main flake definition with inputs and outputs
- `hosts/` - Per-machine NixOS configurations
- `modules/` - Reusable NixOS and home-manager modules
- `lib/` - Helper functions and utilities
- `pkgs/` - Custom package definitions
- `resources/` - Shared resources (SSH keys, etc.)
- `secrets/` - SOPS-encrypted secrets

## Key Patterns

- Modules use `lib.mkEnableOption` and `lib.mkOption` for configuration
- Home-manager modules are in `modules/features/*/home.nix`
- NixOS modules are in `modules/features/*/nixos.nix`
- Hosts import common modules and machine-specific config

## Commands

- `nixos-rebuild switch --flake .` - Apply NixOS config
- `home-manager switch --flake .` - Apply home-manager config
- `nix flake check` - Validate flake
- `nix flake update` - Update inputs

## Best Practices

- Use `lib.mkDefault` for overridable defaults
- Use `lib.mkIf` for conditional config
- Use `lib.mkMerge` to combine multiple config blocks
- Prefer attribute sets over lists where possible
