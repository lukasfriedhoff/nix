# Backup Procedures

This document describes backup and recovery procedures for critical data managed by this repository.

## Secrets Backup

### SOPS Age Keys

Each host has an Age key stored at:
```
/home/lukasf/.config/sops/age/keys.txt  # Desktops
/var/lib/sops-nix/age/keys.txt          # Servers
```

On personal desktops the user key is additionally bootstrapped to
`/var/lib/sops-nix/age/keys.txt` so sops-nix can decrypt system secrets.

**Backup procedure:**
1. Export the key to a secure location (encrypted USB, password manager)
2. Store the public key in the nix-secrets repo's `.sops.yaml` for the host

**Recovery:**
1. Copy the Age key to the appropriate location
2. Run `sops updatekeys` on any secrets that need re-encryption

### Secret Files

All secrets are stored encrypted in the private nix-secrets repo under
`secrets/profiles/`, organized by:
- `common/shared/` - Cross-profile secrets
- `personal/desktops/<host>/` - Personal desktop secrets
- `personal/servers/<host>/` - Personal server secrets
- `work/desktops/<host>/` - Work desktop secrets
- `work/servers/<host>/` - Work server secrets

Secrets are automatically backed up via the nix-secrets repo's git history.
The encryption keys (Age) must be backed up separately.

## SSH Keys

### Management Keys

Management SSH keys for server access are created via:
```bash
./scripts/servers/create-management-key.sh <host> <personal|work>
```

Keys are stored encrypted in the nix-secrets repo under:
- manager paths (private + public): `secrets/profiles/personal/desktops/common/ssh/` or `secrets/profiles/work/desktops/macbook-pro/ssh/`
- host paths (public): `secrets/profiles/<profile>/servers/<host>/ssh/`

### Backup Considerations

- Private keys are SOPS-encrypted in the nix-secrets repo's git history
- SSH key deployment mappings are tracked in `resources/ssh/keys.nix`
- Host SSH keys are generated during installation

## Disaster Recovery Checklist

### Lost Desktop

1. Install NixOS from ISO
2. Restore Age key from backup
3. Clone this repository
4. Run `nixos-rebuild switch --flake .#<hostname>`
5. Run `home-manager switch --flake .#<user>@<hostname>`

### Lost Server

1. Boot NixOS installer ISO
2. Run deployment script: `./scripts/servers/deploy-from-iso.sh <host>`
3. Restore Age key to the server
4. Verify services: `systemctl status`

### Lost All Encryption Keys

If all Age keys are lost:
1. Generate new Age keys for each host
2. Update the nix-secrets repo's `.sops.yaml` with new public keys
3. Re-encrypt all secrets in the nix-secrets checkout: `sops updatekeys secrets/**/*.yaml`
4. Commit (in nix-secrets) and deploy

**Prevention**: Store Age private keys in multiple secure locations.
