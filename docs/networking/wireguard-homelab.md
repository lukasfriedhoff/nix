## Homelab WireGuard edge

The MikroTik at Rüttenscheider Straße exposes a WireGuard hub (endpoint
stored in `secrets/profiles/common/shared/wireguard/endpoint.txt`). Every personal machine now has a
`wg-homelab` interface that can be enabled declaratively.

### Addresses per host

| Host            | Address / CIDR  | Private key secret                                                           |
|-----------------|-----------------|------------------------------------------------------------------------------|
| tux-h4xx-01     | `10.1.90.2/24`  | `secrets/profiles/personal/desktops/tux-h4xx-01/wireguard/homelab.priv`     |
| tab-h4xx-02     | `10.1.90.3/24`  | `secrets/profiles/personal/desktops/tab-h4xx-02/wireguard/homelab.priv`     |
| srv4-vm-01      | `10.1.90.4/24`  | `secrets/profiles/personal/servers/srv4-vm-01/wireguard/homelab.priv`       |

Shared settings (used by every personal host):

| Purpose   | Secret path (edit with `sops`)      |
|-----------|-------------------------------------|
| Domain    | `secrets/profiles/common/shared/wireguard/domain.txt` (contains the search suffix, e.g. `example.lan`) |
| Endpoint  | `secrets/profiles/common/shared/wireguard/endpoint.txt` (contains `host-or-ip:port`) |

> **Note:** The Supermicro server does not yet have an AGE key configured, so
> it is excluded until we can encrypt a private key for it.

### Editing the private keys

Each secret file is a SOPS-encrypted blob seeded with `CHANGE-ME…` placeholders; the actual values are never committed.
Populate the host private key and shared settings as follows:

```bash
# edit shared domain/endpoint once
sops secrets/profiles/common/shared/wireguard/domain.txt
sops secrets/profiles/common/shared/wireguard/endpoint.txt

# per host private key
sops secrets/profiles/personal/desktops/tux-h4xx-01/wireguard/homelab.priv
# replace the placeholder with the real key, save and exit
```

Repeat for `tab` and `srv4`. The files are encrypted with the per-host age
recipient defined in `.sops.yaml`, so only that machine (plus the admin box)
can decrypt them.

### Bringing the tunnel up

After editing the secrets run:

```bash
sudo nixos-rebuild switch --flake .#tux-h4xx-01
sudo systemctl status wg-quick@wg-homelab.service
```

The interface is declaratively defined, so it will auto-start on boot and
set the DNS search domain pulled from `domain.txt` via `resolvectl`.
