---
name: wireguard
description: WireGuard VPN configuration
globs:
  - "**/wireguard/**"
  - "**/*.wg"
  - "**/wg*.conf"
---

# WireGuard Skill

WireGuard VPN configuration in NixOS.

## NixOS Configuration

```nix
networking.wireguard.interfaces.wg0 = {
  ips = [ "10.0.0.2/24" ];
  privateKeyFile = "/run/secrets/wg-private";
  listenPort = 51820;

  peers = [{
    publicKey = "peer-public-key";
    endpoint = "server.example.com:51820";
    allowedIPs = [ "10.0.0.0/24" ];
    persistentKeepalive = 25;
  }];
};
```

## Key Generation

```bash
wg genkey | tee private.key | wg pubkey > public.key
wg genpsk > preshared.key
```

## Commands

```bash
wg show                  # Show interfaces
wg-quick up wg0          # Bring up interface
wg-quick down wg0        # Bring down interface
```

## Split Tunneling

```nix
# Only route specific IPs through VPN
allowedIPs = [ "10.0.0.0/24" "192.168.1.0/24" ];

# Route all traffic (full tunnel)
allowedIPs = [ "0.0.0.0/0" "::/0" ];
```

## Firewall

```nix
networking.firewall = {
  allowedUDPPorts = [ 51820 ];
  trustedInterfaces = [ "wg0" ];
};
```

## Best Practices

- Store private keys in SOPS
- Use persistentKeepalive for NAT traversal
- Set appropriate AllowedIPs for security
