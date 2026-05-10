---
name: ssh
description: SSH configuration and key management
globs:
  - "**/ssh/**"
  - "**/.ssh/**"
  - "**/ssh_config"
---

# SSH Skill

SSH configuration and key management in NixOS.

## NixOS SSH Config

```nix
programs.ssh = {
  enable = true;
  matchBlocks = {
    "myhost" = {
      hostname = "192.168.1.10";
      user = "admin";
      identityFile = "~/.ssh/mykey";
      port = 22;
    };
    "*.internal" = {
      proxyJump = "bastion";
    };
  };
};
```

## Key Generation

```bash
ssh-keygen -t ed25519 -C "comment"
ssh-keygen -t rsa -b 4096 -C "comment"
```

## Agent Configuration

```nix
programs.ssh.addKeysToAgent = "yes";
services.ssh-agent.enable = true;
```

## Host Key Verification

```nix
programs.ssh.extraConfig = ''
  StrictHostKeyChecking accept-new
'';
```

## Common Options

```nix
{
  forwardAgent = true;
  extraOptions = {
    AddKeysToAgent = "yes";
    IdentitiesOnly = "yes";
  };
}
```

## Best Practices

- Use Ed25519 keys for new setups
- Set `IdentitiesOnly yes` to prevent key spam
- Use ProxyJump for bastion hosts
- Store keys in SOPS for declarative management
