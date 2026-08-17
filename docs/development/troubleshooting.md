# Troubleshooting Guide

This guide provides solutions for common issues encountered when working with this Nix configuration system.

## Common Issues and Solutions

### NixOS Configuration Build Failures

#### Generic Build Errors
If `nixos-rebuild` fails:
1. Check the error message for specific details
2. Ensure all referenced modules are available
3. Verify option types and values match expected formats
4. Run `nix flake check` to validate the entire flake

#### Option Validation Errors
If options fail validation:
```bash
# Example error: "Option 'lukasf.<feature>.port' is not of type 'port'"
# Check the option definition and correct the value type
lukasf.<feature>.port = 8080;  # Should be an integer, not string
```

#### Missing Dependencies
If configuration depends on missing packages:
```nix
# Ensure packages are available in the module
environment.systemPackages = [ cfg.package ];
```

### Secrets and Encryption Issues

#### SOPS Decryption Failures
If secrets can't be decrypted:
1. Verify the SOPS file paths are correct
2. Check that your age key is available (run against the nix-secrets checkout,
   default `../nix-secrets`):
```bash
sops decrypt ../nix-secrets/secrets/profiles/personal/desktops/<hostname>/wireguard/homelab.priv
```

3. Confirm the key permissions are correct (age key file should be readable)

#### Missing Secrets Directories
If SOPS can't find secret directories:
1. Ensure proper entry in `secretsByProfile` in `flake.nix`
2. Check the nix-secrets repo's `.sops.yaml` key entries for the host
3. Confirm the directory structure exists in the nix-secrets checkout
   (`NIX_SECRETS_DIR`, default `../nix-secrets`) and the flake input is fresh
   (`nix flake update nix-secrets` after pushing new secrets)

### Hardware and Boot Issues

#### Hardware Detection Failures
If hardware detection fails:
1. Run `scripts/hardware-survey.sh` to generate facter data
2. Manually adjust hardware configurations if needed
3. Check that `hardwareProfiles` are correctly enabled

#### Boot and Initrd Issues
If boot fails:
1. Check `boot.initrd.availableKernelModules` for required modules
2. Verify root device paths
3. Review `hardware-configuration.nix` for any incorrect settings

### Network and Firewall Problems

#### Port Access Issues
If services aren't accessible:
1. Verify the service is actually enabled
2. Check `networking.firewall` rules
3. Confirm `openFirewall` options are set correctly for the feature

#### VPN and Proxy Failures
If network connectivity fails:
1. Check that WireGuard secrets are correctly set
2. Verify VPN configuration in `secretsByProfile`
3. Confirm that the service is running with `systemctl status`

### Performance and System Issues

#### Slow System Boot
If the system boots slowly:
1. Review `boot.initrd` module loading
2. Check for unnecessary services
3. Consider using `systemd` debug modes

#### High Resource Usage
If processes consume unusual resources:
1. Check `systemd` service units for resource limits
2. Review configurations that may be intensive (backups, updates, etc.)
3. Use `top`, `htop`, or `journalctl` to identify culprits

### Host Configuration Issues

#### Module Enablement Problems
If enabling modules doesn't work:
1. Check that the module path is correct in imports
2. Verify option namespaces (`lukasf.<feature>`, `desktop.<feature>`, etc.)
3. Confirm `enable = true` or equivalent is set correctly

#### Overrides Not Working
If host overrides are ignored:
1. Check for `lib.mkForce` usage which can override options
2. Ensure module imports are in correct order
3. Review that overrides are applied at the right scope

### Git and Version Control Issues

#### Staging and Commit Problems
If commits fail due to pre-commit hooks:
1. Run `nix fmt` to fix formatting issues
2. Check for unencrypted secrets in staged files
3. Run `nix flake check` to verify syntax before commit

#### Merge Conflicts and Updates
When updating configurations:
1. Use `git pull --rebase` to integrate changes
2. Resolve conflicts in `flake.nix` and host configurations (secrets live in the separate nix-secrets repo)
3. Test all configs after updates

## Diagnostic Commands

### Nix-related Diagnostics
```bash
# Check flake syntax
nix flake check

# Show the current configuration
nixos-rebuild build --flake .#<hostname>

# Test configuration without applying
nixos-rebuild test --flake .#<hostname>

# Verify secrets can be decrypted (in the nix-secrets checkout)
sops decrypt ../nix-secrets/secrets/path/to/secret.yaml
```

### System-related Diagnostics
```bash
# Check if services are running
systemctl status <service>

# View service logs
journalctl -u <service> -n 100

# Check disk space
df -h

# Check package versions
nix info --system <system> --show-trace

# List installed packages
nix-env -q
```

### Network Diagnostics
```bash
# Check network connectivity
ping 8.8.8.8

# Check open ports
nmap localhost

# View firewall status
sudo iptables -L

# Check DNS resolution
nslookup <domain>
```

## Debugging Techniques

### Using Nix Debug Options
```bash
# Enable verbose output
nixos-rebuild build --flake .#<hostname> -v

# Enable tracing
nixos-rebuild build --flake .#<hostname> --show-trace

# View evaluated configuration
nixos-rebuild build --flake .#<hostname> --dry-run
```

### Module and Option Investigation
```bash
# Check available options for a module
nixos-option lukasf.<feature>

# Show all available modules
nixos-option --all

# Check module evaluation
nix-instantiate --eval -E 'import ./<path>/default.nix { }'
```

## Prevention Strategies

### Code Quality
- Run `nix fmt` before committing changes
- Ensure all new modules follow the established patterns
- Test new features in development configurations first
- Maintain clear, descriptive documentation

### Security
- Always use SOPS-encrypted secrets
- Never commit private keys or unencrypted credentials
- Regularly review secret access permissions
- Check for outdated or unused secrets

### Maintenance
- Regularly backup critical configurations and secrets
- Test deployments in staging before production
- Monitor system performance and health
- Keep documentation updated with code changes