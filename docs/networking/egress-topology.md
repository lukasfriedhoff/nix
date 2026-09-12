# Homelab egress topology & measured throughput (2026-09-12)

Corrected analysis after the "why is nextcloud slow via Cloudflare" investigation.
Earlier assumptions (DSL uplink bottleneck) were **wrong** — this documents what
was actually measured.

## The path

```
visitor browser
   │ HTTPS
   ▼
Cloudflare edge (fra)          ← static assets cached here (cf-cache-status: HIT)
   │ QUIC tunnel (cloudflared, 2 replicas on srv2/srv8)
   ▼
cloudflared pod → traefik → app pods
   │ node egress (vlan30-MANAGEMENT)
   ▼
RB5009 → wg-proton-prod (WireGuard, MTU 1420) → ProtonVPN exit (149.88.x / 2a02:6ea0::)
   │
   ▼
Telekom FIBER via pppoe-telekom (NOT DSL)
```

- ALL homelab VLANs in interface-list `homelab-vpn-vlans` egress through
  ProtonVPN; a kill-switch rule drops direct-WAN leaks
  (`drop dst!=homelab-local-v4 in=homelab-vpn-vlans out=WAN`).
- Cluster nodes' public identity = the Proton exit IP, v4 and v6.

## Measured numbers (2026-09-12, all through the Proton path)

| Leg | Measured |
|---|---|
| srv9 → internet upload (CF /__up) | **20.3 MB/s (~162 Mbit)** |
| srv9 → nextcloud **through the full CF tunnel** | **12.1 MB/s (~97 Mbit)** |
| tux (desktop, wifi) ← CF edge direct | **5.7 MB/s (~45 Mbit)** |
| tux ← nextcloud via tunnel, single stream | ~1.3 MB/s |
| tux page load, ~20 parallel cold requests | 0.05–0.5 MB/s per stream (4–11 s each) |

## Conclusions

1. **Fiber + Proton + the cloudflared tunnel are fast** (~100 Mbit end-to-end
   through every server-side hop). The tunnel/QUIC-over-WireGuard stack is NOT
   the bottleneck (occasional transient `QUIC stream timeout` in cloudflared
   logs, but throughput is fine).
2. **The perceived slowness is client-side**: the desktop's ~45 Mbit wifi path
   divided by ~20 parallel requests during a cold page load. A cold load only
   happens when the Nextcloud asset version bumps (every helm config rollout
   invalidates all `?v=` URLs — batch config changes!).
3. Cloudflare edge caching works as designed (`immutable, max-age=1y` on
   /dist and app JS; theming icons are `private` by NC design and always
   origin-fetched — small files, latency-bound).
4. Historic note: the old "~690 KB/s tunnel cap" memory was a misattribution —
   likely the same client-side/wifi split observed on an earlier day.

## Levers (ranked)

1. ~~Split-horizon DNS~~ — proposed, **declined by operator 2026-09-12**
   (do not re-propose).
2. Wire the desktop / improve its wifi (45 Mbit is the session ceiling).
3. Avoid unnecessary asset-version bumps (batch nextcloud config rollouts).
4. Nothing to fix on fiber/Proton/tunnel — measured healthy.

## Related

- `wireguard-homelab.md` — VPN topology
- NAS/media path: 10.1.120.10 (vlan120-GuestServers) reachable from nodes via
  masquerade rule "k3s nodes -> NAS NFS" (NAS lacks a return route; fix =
  gateway 10.1.120.1 on the NAS, then the NAT rule can be disabled).
  Line-rate measured: 110 MB/s read, 90 MB/s write.
