# NixOS Facter Evaluation

This document evaluates nixos-facter for potential adoption in this repository.

## What is nixos-facter?

nixos-facter is a hardware detection tool that generates machine-readable JSON reports,
which NixOS modules can use to automatically configure hardware-specific settings.

- **Repository**: [nix-community/nixos-facter](https://github.com/nix-community/nixos-facter)
- **Modules**: [nix-community/nixos-facter-modules](https://github.com/nix-community/nixos-facter-modules)

## How It Works

1. **Scan hardware**: `sudo nix run nixpkgs#nixos-facter -- -o facter.json`
2. **Import in NixOS**: `hardware.facter.reportPath = ./facter.json;`
3. **Automatic configuration**: Modules enable features based on detected hardware

## Current Approach vs nixos-facter

### Current Approach

We use manual hardware modules per device model:

```
modules/nixos/hardware/
├── asus/vivobook-t3300.nix
├── supermicro/amd7900xtx.nix
└── tuxedo/infinitybook-pro-16-gen8.nix
```

Each module explicitly configures:
- GPU drivers and settings
- Firmware packages
- Kernel parameters
- Power management
- Device-specific quirks

### nixos-facter Approach

A single JSON file per host describes hardware, and modules auto-configure:

```nix
{ hardware.facter.reportPath = ./hosts/tux-h4xx-01/facter.json; }
```

## Comparison

| Aspect | Current | nixos-facter |
|--------|---------|--------------|
| Hardware detection | Manual | Automatic |
| GPU configuration | Explicit bus IDs | Auto-detected |
| Kernel modules | Listed in hardware-configuration.nix | Auto from facter |
| Quirk handling | Custom modules | Limited support |
| Maintenance | Update modules manually | Re-run facter |
| Reproducibility | Fully declarative | JSON + modules |

## Recommendation

**Keep current approach with selective facter adoption.**

### Why Keep Custom Modules

1. **Complex GPU setups**: NVIDIA Prime with specific bus IDs, offload vs sync modes
2. **Device quirks**: ACPI GPE masks, SD card quirks, kernel parameters
3. **Fine-grained control**: Power management tuning, thermal profiles
4. **Stability**: Known working configurations vs auto-detection

### Where to Use nixos-facter

1. **New server deployments**: Generate facter.json during installation
2. **Basic hardware**: Servers without complex GPU or power requirements
3. **Documentation**: Use facter reports as hardware inventory

## Adoption Path

If adopting nixos-facter:

```nix
# flake.nix inputs
inputs.nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";

# Host configuration
{
  imports = [
    inputs.nixos-facter-modules.nixosModules.facter
    ./hardware-configuration.nix
    # Keep custom module for quirks
    ../../modules/nixos/hardware/tuxedo/infinitybook-pro-16-gen8.nix
  ];

  # Let facter handle basic detection
  hardware.facter.reportPath = ./facter.json;

  # Override specific settings in custom module
}
```

## Generating facter.json

```bash
# On the target system
sudo nix run nixpkgs#nixos-facter -- -o facter.json

# Commit to repository
cp facter.json /path/to/nix/hosts/<hostname>/
git add hosts/<hostname>/facter.json
```

## References

- [nixos-facter announcement](https://discourse.nixos.org/t/nixos-facter-declarative-hardware-configuration-for-nixos/52083)
- [Introducing NixOS Facter - Clan Blog](https://clan.lol/blog/nixos-facter/)
