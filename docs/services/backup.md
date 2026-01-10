# Backup Procedures

This document describes backup and recovery procedures for critical data managed by this repository.

## Secrets Backup

### SOPS Age Keys

Each host has an Age key stored at:
```
/home/lukasf/.config/sops/age/keys.txt  # Desktops
/var/lib/sops-nix/age/keys.txt          # Servers
```

**Backup procedure:**
1. Export the key to a secure location (encrypted USB, password manager)
2. Store the public key in `.sops.yaml` for the host

**Recovery:**
1. Copy the Age key to the appropriate location
2. Run `sops updatekeys` on any secrets that need re-encryption

### Secret Files

All secrets are stored encrypted in `secrets/profiles/` organized by:
- `common/shared/` - Cross-profile secrets
- `personal/desktops/<host>/` - Personal desktop secrets
- `personal/servers/<host>/` - Personal server secrets
- `work/desktops/<host>/` - Work desktop secrets
- `work/servers/<host>/` - Work server secrets

Secrets are automatically backed up via git. The encryption keys (Age) must be backed up separately.

## Ceph Key Backup

The Ceph module (`lukasf.ceph`) provides automatic encrypted backups when `backup.enable = true`.

### Backup Location

```
/var/lib/ceph/backup/ceph-keys-<fsid>-<timestamp>.tar.gz.enc
```

### What's Backed Up

- OSD lockbox keyrings
- Client keyrings
- Cluster configuration

### Backup Schedule

- **Frequency**: Daily at 03:00
- **Retention**: 30 days

### Encryption

Backups are encrypted with AES-256-CTR using a passphrase stored as a SOPS secret:
```
secrets/profiles/personal/servers/ceph/<fsid>/backup.key
```

### Restore Procedure

```bash
# Decrypt the backup passphrase
tmp_dir="$(mktemp -d)"
sops -d secrets/profiles/personal/servers/ceph/<fsid>/backup.key > "$tmp_dir/backup.key"

# Decrypt the backup archive
openssl enc -d -aes-256-ctr -pbkdf2 -salt -md sha256 \
  -pass "file:$tmp_dir/backup.key" \
  -in /var/lib/ceph/backup/ceph-keys-<fsid>-<timestamp>.tar.gz.enc \
  -out "$tmp_dir/ceph-keys.tar.gz"

# Inspect contents first
tar -tzf "$tmp_dir/ceph-keys.tar.gz"

# Restore keyrings (carefully!)
tar -xzf "$tmp_dir/ceph-keys.tar.gz" -C /

# Cleanup
rm -rf "$tmp_dir"
```

## SSH Keys

### Management Keys

Management SSH keys for server access are created via:
```bash
./scripts/servers/create-management-key.sh <host>
```

Keys are stored encrypted in `secrets/profiles/<profile>/ssh/`.

### Backup Considerations

- Private keys are SOPS-encrypted in git
- Public keys are stored in `resources/ssh/keys/`
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
4. For Ceph nodes: restore keyrings from backup
5. Verify services: `systemctl status`

### Lost Ceph OSD

1. Replace failed disk
2. Update `resources/homelab/disks.nix` with new device path
3. Set `lukasf.ceph.osd.zapDevices = true` temporarily
4. Deploy configuration
5. Revert `zapDevices = false`
6. Monitor recovery: `ceph -s`

### Lost All Encryption Keys

If all Age keys are lost:
1. Generate new Age keys for each host
2. Update `.sops.yaml` with new public keys
3. Re-encrypt all secrets: `sops updatekeys secrets/**/*.yaml`
4. Commit and deploy

**Prevention**: Store Age private keys in multiple secure locations.
