## Homelab WireGuard edge

The MikroTik at Rüttenscheider Straße exposes a WireGuard hub (endpoint
stored in `secrets/profiles/personal/shared/wireguard/endpoint.txt`). Every personal machine now has a
`wg-homelab` interface that can be enabled declaratively.

All secret paths in this document live in the private nix-secrets repo; run
`sops` from that checkout (default `../nix-secrets`, override with
`NIX_SECRETS_DIR`).

### Addresses per host

| Host            | Address / CIDR  | Private key secret                                                           |
|-----------------|-----------------|------------------------------------------------------------------------------|
| tux-h4xx-01     | `10.1.90.2/24`  | `secrets/profiles/personal/desktops/tux-h4xx-01/wireguard/homelab.priv`     |
| tab-h4xx-02     | `10.1.90.3/24`  | `secrets/profiles/personal/desktops/tab-h4xx-02/wireguard/homelab.priv`     |
| lenovo-h4xx-03  | `10.1.90.5/24`  | `secrets/profiles/personal/desktops/lenovo-h4xx-03/wireguard/homelab.priv`  |
| srv4-vm-01      | `10.1.90.4/24`  | `secrets/profiles/personal/servers/srv4-vm-01/wireguard/homelab.priv`       |

Shared settings (used by every personal host):

| Purpose   | Secret path (edit with `sops`)      |
|-----------|-------------------------------------|
| Domain    | `secrets/profiles/personal/shared/wireguard/domain.txt` (contains the search suffix, e.g. `example.lan`) |
| Endpoint  | `secrets/profiles/personal/shared/wireguard/endpoint.txt` (contains `host-or-ip:port`) |

> **Note:** The Supermicro server does not yet have an AGE key configured, so
> it is excluded until we can encrypt a private key for it.

### Editing the private keys

Each secret file is a SOPS-encrypted blob seeded with `CHANGE-ME…` placeholders; the actual values are never committed.
Populate the host private key and shared settings as follows:

```bash
# edit shared domain/endpoint once
sops secrets/profiles/personal/shared/wireguard/domain.txt
sops secrets/profiles/personal/shared/wireguard/endpoint.txt

# per host private key
sops secrets/profiles/personal/desktops/tux-h4xx-01/wireguard/homelab.priv
# replace the placeholder with the real key, save and exit
```

Repeat for `tab`, `lenovo`, and `srv4`. The files are encrypted with the per-host age
recipient defined in the nix-secrets repo's `.sops.yaml`, so only that machine
(plus the admin box) can decrypt them.

### Bringing the tunnel up

After editing the secrets run:

```bash
sudo nixos-rebuild switch --flake .#tux-h4xx-01
sudo systemctl status wireguard-wg-homelab.service
```

The interface is declaratively defined, so it will auto-start on boot and
set the DNS search domain pulled from `domain.txt` via `resolvectl`.

Current defaults use DNS via the WireGuard gateway first (`10.1.90.1`)
and health checks target `10.1.90.1`. The interface MTU is set to `1320`
because nested VPN paths can pass small packets while stalling larger TLS/SSH
handshakes. On `tux-h4xx-01`, `ping -M do` to `srv2` passed at payload `1300`
and failed at payload `1360`, so `1320` keeps TCP below the observed path MTU.

### Start from the user session (laptops)

If Wi-Fi is not available at boot, you can defer startup to the user session:

```nix
lukasf.wireguard.homelab.userUnit.enable = true;
```

Then check from your session:

```bash
systemctl --user status wireguard-wg-homelab.service
```

When user-mode startup is enabled, the periodic system refresh timer is
disabled to avoid restarting the tunnel every few minutes.

### Preshared keys (post-quantum hardening)

Each host has a SOPS-encrypted PSK in nix-secrets at
`secrets/profiles/personal/<desktops|servers>/<host>/wireguard/homelab-psk.txt`.
A PSK adds a symmetric layer that stays secure against quantum attacks on
Curve25519 ("harvest now, decrypt later").

Rollout order matters — the MikroTik must know the PSK first:

1. Read the host's PSK: `sops -d secrets/profiles/personal/desktops/tux-h4xx-01/wireguard/homelab-psk.txt`
2. On the MikroTik, set it on the matching peer:
   `/interface/wireguard/peers set [find comment="tux-h4xx-01"] preshared-key="<psk>"`
3. Only then enable it on the host:

   ```nix
   sops.secrets."wireguard-homelab-psk" = {
     sopsFile = "${secrets.primary}/wireguard/homelab-psk.txt";
     format = "binary";
   };
   lukasf.wireguard.homelab.presharedKeyFile =
     config.sops.secrets."wireguard-homelab-psk".path;
   ```

The module option defaults to null, so nothing changes until a host opts in.
