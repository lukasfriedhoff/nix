---
name: sops-secrets
description: SOPS and age encryption for secrets management
globs:
  - "**/.sops.yaml"
  - "**/secrets/**"
  - "**/*.sops.*"
---

# SOPS Secrets Skill

Managing encrypted secrets with SOPS and age in NixOS.

## Key Files

- `.sops.yaml` - SOPS configuration with age keys and path rules
- `secrets/` - Encrypted secret files

## Commands

```bash
# Encrypt a file
sops -e secrets/plain.yaml > secrets/encrypted.yaml

# Edit encrypted file
sops secrets/encrypted.yaml

# Decrypt to stdout
sops -d secrets/encrypted.yaml

# Rotate keys
sops updatekeys secrets/encrypted.yaml
```

## NixOS Integration

```nix
sops.secrets.my-secret = {
  sopsFile = ./secrets/file.yaml;
  owner = "user";
  group = "group";
  mode = "0400";
};
```

## Age Key Management

- Host keys: `/etc/ssh/ssh_host_ed25519_key`
- User keys: `~/.config/sops/age/keys.txt`
- Convert SSH to age: `ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`

## Best Practices

- Never commit unencrypted secrets
- Use per-host age keys derived from SSH host keys
- Define creation_rules in `.sops.yaml` for automatic key selection
