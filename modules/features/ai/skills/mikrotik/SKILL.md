---
name: mikrotik
description: MikroTik RouterOS 7 operations — homelab RB5009 topology, safe read-only inspection, VLAN/firewall/NAT/WireGuard patterns, and RouterOS CLI gotchas
---

# MikroTik / RouterOS Skill

Operating the homelab's MikroTik routers (primary: **RB5009**, `ssh mikrotikrb5009`;
secondary site: `mikrotikhiesfelder`). RouterOS 7.x.

## Homelab RB5009 topology (discovered 2026-09-12)

- **WAN**: `pppoe-telekom` on Telekom **fiber** (+ `vlan2002-5gmodem` backup WAN).
- **VLANs** (bridge, `vlanX-NAME`, gateway `10.1.X.1/24` unless noted):
  05-h4xx (10.0.10.0/23), 7-Telekom, 10-LAN, 11-WIFI, 12-IOT, 13-WINDOWS,
  15-openwrtLAN, 20-SERVER, 30-MANAGEMENT (k3s nodes: srv2=.26 srv8=.27
  srv9=.31), 40-STORAGE (storage01=.244), 50-LAB, 60-Guest, 61-other,
  **120-GuestServers (NAS 10.1.120.10)**; `wg-clients` (10.1.90.0/24).
- **Egress**: interface-list `homelab-vpn-vlans` routes through
  `wg-proton-prod` (ProtonVPN WireGuard, MTU 1420) with a kill-switch
  (`drop dst-address-list=!homelab-local-v4 in-interface-list=homelab-vpn-vlans
  out-interface-list=WAN`). Cluster egress IP = Proton exit (149.88.x).
  Measured: ~160 Mbit up through Proton — the VPN is not a bottleneck.
- **Site-to-site WG**: `wg-s2s-rue`, `wg-s2s-travel`, `wg-s2s-hiesfelder`.
- **Guest isolation**: `vlan120: no access to local networks` (drop
  dst=homelab-local-v4 in=vlan120) — guests can't initiate inward; replies to
  outbound connections ride established/related. Keep this rule.
- **NAS reachability**: NAS 10.1.120.10 has NO return route off its subnet →
  srcnat rule `k3s nodes -> NAS NFS (media migration)` masquerades
  10.1.30.0/24 → NAS (so the NAS sees on-link 10.1.120.1). Disable it once
  the NAS gets gateway 10.1.120.1.

## CLI gotchas (learned the hard way)

- `print brief where <cond>` fails on ROS7 — use `print where chain=forward`
  (no `brief` before `where`).
- Long outputs wrap; pipe through `grep -vE "WARNING|openssh"` to drop the
  post-quantum SSH warnings (the RB5009's sshd predates PQ KEX — known,
  see pq-crypto-migration memory).
- Find-by-comment is the safest mutation targeting:
  `/ip firewall nat disable [find comment~"NAS NFS"]`.
- Firewall rule ORDER matters and prints are ordered but numbered sparsely;
  use `place-before=` when adding rules that must precede a drop.
- On-link vs routed testing: `/ping 10.1.120.10` sources from the connected
  interface (tests L2 liveness); `/ping X src-address=10.1.30.1` tests the
  target's RETURN routing — the two together isolate "host up but no return
  route" in seconds.

## Safe inspection commands (read-only)

```
/ip address print                 # VLANs + subnets
/interface vlan print             # VLAN ids
/interface list member print      # LAN/WAN/vpn-vlans membership
/ip route print brief             # routing incl. VPN defaults
/ip firewall filter print where chain=forward
/ip firewall nat print
/interface wireguard print        # tunnels (proton, s2s, clients)
/interface wireguard peers print
/ip arp print where address~"10.1.120"
/ping <ip> count=3 [src-address=<gw-ip>]
/interface monitor-traffic <iface> once
```

## Change patterns

- **Temporary NAT for an unrouted device** (e.g. NAS without gateway):
  `/ip firewall nat add chain=srcnat src-address=<clients> dst-address=<dev>
  out-interface=<dev-vlan> action=masquerade comment="..."` — the device sees
  its own gateway IP; remember its allow-lists must then permit that IP.
- **Pin an explicit inter-VLAN accept** (auditability, before future drops):
  `/ip firewall filter add chain=forward action=accept protocol=tcp
  src-address=10.1.30.0/24 dst-address=<dev> dst-port=2049 comment="..."`.
- **Split-horizon DNS**: `/ip dns static add name=<host> address=<lan-vip>`
  (clients must use the router's DNS).
- Prefer `disable` over `remove` for rules you might roll back; comment
  everything (comments are the only sane handle for find).
- Config export for review: `/export compact` (redacts nothing — treat as
  secret material; never commit it).
