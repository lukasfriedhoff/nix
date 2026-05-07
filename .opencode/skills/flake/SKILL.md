---
name: flake
description: Nix flake structure, inputs, outputs, and overlays
globs:
  - "flake.nix"
  - "flake.lock"
---

# Nix Flake Skill

Modern Nix project structure with flakes.

## Flake Structure

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./configuration.nix ];
      specialArgs = { inherit inputs; };
    };
  };
}
```

## Overlays

```nix
overlays = [
  (final: prev: {
    myPackage = prev.myPackage.override { };
  })
];
```

## Commands

```bash
nix flake check          # Validate flake
nix flake update         # Update all inputs
nix flake lock --update-input nixpkgs  # Update single input
nix flake show           # Show outputs
nix flake metadata       # Show inputs and revisions
```

## Special Args

Pass extra arguments to modules:
```nix
specialArgs = { inherit inputs; profile = "desktop"; };
```

## Best Practices

- Pin inputs with `follows` to reduce duplicates
- Use `nixpkgs.follows` for consistent package versions
- Keep flake.lock in version control
