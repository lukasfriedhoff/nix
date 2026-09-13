---
name: homelab-node-join
description: Wipe a bare-metal box and join it to the homelab k3s cluster via nix — encrypted Longhorn SSD storage, nixos-facter, IPMI-ISO boot, Hydra/Attic build pipeline. Use when re-provisioning or adding a homelab node (srvN).
---

# Homelab node: wipe + join to k3s (via nix)

End-to-end procedure to (re)provision a homelab server as a k3s node with
LUKS-encrypted Longhorn data disks. Validated on srv1 (2026-09-13). Layers:
nix (`nix/`) provisions the host; it auto-joins k3s + Flux on boot.

## 0. Decide role FIRST (it changes the config + etcd health)

- **agent** — worker + Longhorn storage. **Default.** etcd quorum is
  unchanged. An agent MUST NOT set `gitops` (the module asserts
  `gitops.enable -> role == "server"`; Flux is bootstrapped by the servers).
- **server** — control-plane/etcd member. Only add to keep the etcd count
  **odd** (3 or 5). 4 servers is strictly worse than 3. Servers may run
  gitops.
- Longhorn runs on agents too, so a storage node does NOT need to be a server.

## 1. Boot the target into the NixOS installer

IPMI virtual media over SMB is the no-hands path (see the `mikrotik`/samba
notes). Serve the minimal ISO from any docker/podman host reachable by the
BMC:
```
podman run -d --name nixos-iso-smb --restart unless-stopped -p 445:445 -p 139:139 \
  -v /opt/nixos-iso:/share:ro,z docker.io/dperson/samba -p \
  -g "server min protocol = NT1" -g "ntlm auth = yes" \
  -s "iso;/share;yes;yes;yes;all;none;" -u "nixos;<pw>"
```
Mount `\\<smb-host>\iso\<minimal>.iso` in IPMI virtual media, boot it. The
ISO channel need NOT match the flake (nixos-anywhere builds the target from
the flake); latest stable minimal is fine. **Set a root password on the
installer console (`passwd`)** — nixos-anywhere needs root SSH.

## 2. Recon on the installer (before touching nix)

```
ssh-keygen -R <ip>            # the installer's host key differs from the old OS
ssh root@<ip> 'lsblk -dno NAME,SIZE,MODEL; ls -l /dev/disk/by-id/ | grep -E "ata-|nvme-"'
# facter: generate the hardware report ON the target
ssh root@<ip> 'nix --extra-experimental-features "nix-command flakes" run nixpkgs#nixos-facter' \
  > hosts/homelab/<host>/facter.json
```
Note the **root disk by-id** and every **data-disk by-id** (verbatim).

## 3. Wire the host in nix (`nix/`)

**a) `resources/homelab/disks.nix`** — one entry per DATA disk:
```nix
"ata-<DATA-DISK-ID>" = {
  host = "<host>"; purpose = "longhorn";
  luksKeyFile = "luks/<host>-longhorn.txt";   # shared sops passphrase (per host)
  luksPasswordFile = "/tmp/luks-longhorn.key"; # deploy-time path
  type = "ssd";
};
```
(If migrating off Ceph: replace `purpose="ceph"`+`lockboxKeyFile` with the above.)

**b) `hosts/homelab/<host>/disko.nix`** — copy srv8's pattern: static root
disk (boot 1G EF00 + `root` 100% LUKS `cryptroot` → ext4 `/`, passwordFile
`/tmp/luks.key`) **plus** the dynamic Longhorn block that FORMATS each data
disk (the longhornDisks *module* only opens/mounts — disko must format):
```nix
// lib.genAttrs longhornDiskIds (diskId: { type="disk"; device="/dev/disk/by-id/${diskId}";
  content.type="gpt"; content.partitions.data = { size="100%"; content = {
    type="luks"; name="cryptlonghorn${toString idx}"; passwordFile = lib.head longhornPasswordFiles;
    settings.allowDiscards=true;
    content={ type="filesystem"; format="ext4"; mountpoint="/var/lib/longhorn-disk${toString idx}";
      mountOptions=["defaults" "nofail" "discard"]; }; }; }; })
```

**c) `hosts/homelab/<host>/configuration.nix`**:
```nix
let
  prodApiHost   = "srv2.lab.h4xx.io";
  k3sTokenSecret = "${secrets.primary}/k3s-server-token.txt";
  hasK3sToken    = builtins.pathExists k3sTokenSecret;   # gate: no token -> no rogue clusterInit
in {
  # imports: DROP ./hardware-configuration.nix (facter.json replaces it — the
  #   facter module auto-enables when hosts/<...>/<host>/facter.json exists;
  #   keeping hardware-configuration.nix too double-defines hardware).
  sops.secrets."k3s-server-token" = lib.mkIf hasK3sToken { sopsFile = k3sTokenSecret; owner="root"; format="binary"; mode="0400"; };
  homelab.longhornDisks = { enable = true; sopsFile = "${secrets.profileShared}/luks/<host>-longhorn.txt"; };
  boot.initrd.luks.devices = lib.mkForce { cryptroot = { device = "/dev/disk/by-partlabel/disk-main-root"; allowDiscards = true; }; };  # stage-2 unlocks the data disks
  homelab.kubernetes = lib.mkIf hasK3sToken {
    enable = true; longhorn.enable = true;
    role = "agent";                                   # or "server" (odd etcd!)
    serverAddr = "https://${prodApiHost}:6443";
    tokenFile = config.sops.secrets."k3s-server-token".path;
    nodeIP = "<ip>"; tlsSans = [ "<host>.lab.h4xx.io" "<host>" "<ip>" ];
    # NO gitops block for an agent.
  };
}
```

## 4. Secrets (`nix-secrets/`, private repo)

```
cd nix-secrets
# host age key: scripts/homelab/new-host.sh (or reuse existing servers/<host>/age.key)
# Longhorn LUKS passphrase (binary; --filename-override so sops picks the dest rule):
head -c 32 /dev/urandom | base64 | tr -d '\n' > /tmp/.k
sops --encrypt --input-type binary --output-type binary \
  --filename-override secrets/profiles/personal/shared/luks/<host>-longhorn.txt \
  /tmp/.k > secrets/profiles/personal/shared/luks/<host>-longhorn.txt ; shred -u /tmp/.k
# k3s cluster token: copy an existing node's value (same token for all joiners):
sops -d secrets/profiles/personal/servers/srv8/k3s-server-token.txt > /tmp/.t
sops --encrypt --input-type binary --output-type binary \
  --filename-override secrets/profiles/personal/servers/<host>/k3s-server-token.txt \
  /tmp/.t > secrets/profiles/personal/servers/<host>/k3s-server-token.txt ; shred -u /tmp/.t
git pull --rebase && git add -A && git commit && git push     # ALWAYS pull --rebase first (fast-forward)
```
Then in `nix/`: `nix flake update nix-secrets` (else the build can't see the
new secrets → `hasK3sToken=false` → host silently deploys with no k3s).
`.sops.yaml`: the `personal/shared` + `personal/servers` rules must list the
host's age key (verify: it's a recipient).

## 5. Validate BEFORE deploying (forces assertions)

```
nix eval .#nixosConfigurations.<host>.config.homelab.kubernetes.role   # expect "agent"/"server", not the default
nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath   # must build; catches failed assertions
nix eval .#nixosConfigurations.<host>.config.disko.devices.disk --apply builtins.attrNames  # root + all data disks
```

## 6. Build pipeline

`git push` the host to **develop** → Hydra (tracks develop) builds the
closure into **Attic**. tux already substitutes from
`attic.h4xx.io/homelab` (priority 30), so the deploy's build pulls cached
paths automatically — no flags. Optionally wait for Hydra to finish for a
fully-cached deploy; local build is the fallback (never a hard dependency).

## 7. Deploy (wipes the target)

```
ssh-keygen -R <ip>
scripts/servers/deploy-from-iso.sh <host> root@<ip> \
  --luks-secret ../nix-secrets/secrets/profiles/personal/shared/luks/<host>.txt \
  --disk-secret /tmp/luks-longhorn.key ../nix-secrets/secrets/profiles/personal/shared/luks/<host>-longhorn.txt
```
`--luks-secret` decrypts the ROOT passphrase to `/tmp/luks.key`;
`--disk-secret <path> <sops>` stages the Longhorn passphrase at
`/tmp/luks-longhorn.key` (matches disko's `luksPasswordFile`). Both are
needed. nixos-anywhere kexecs, disko wipes+formats all disks, installs, the
host's age key is provisioned, reboots.

## 8. Verify the join

```
kubectl get nodes            # <host> appears, Ready
kubectl get nodes <host> -o jsonpath='{.metadata.labels}'   # role
# Longhorn adopts /var/lib/longhorn-diskN automatically (longhorn-manager DaemonSet)
kubectl -n longhorn-system get nodes.longhorn.io <host> -o jsonpath='{.spec.disks}'
```

## Gotchas (each cost real time)

- **gitops requires role=server** — agents omit the gitops block or eval fails.
- **etcd must stay odd** — agent unless deliberately going 3→5 servers.
- **disko formats, the module only opens** — data disks MUST be in disko or
  the stage-2 unlock finds no LUKS and fails.
- **facter ⊻ hardware-configuration.nix** — the facter module auto-enables on
  a present `facter.json`; drop the hw-config import or they conflict.
- **sops needs `--filename-override`** when the input path differs from the
  destination (else "no matching creation rules").
- **`git pull --rebase` nix-secrets before push**, then `nix flake update
  nix-secrets` — the build reads the LOCKED rev, not your working tree.
- **`hasK3sToken` gate** — if the token secret is missing at eval, the k3s
  block is silently `mkIf`'d off and the node deploys without joining.
- **clear the stale SSH host key** (`ssh-keygen -R`) — the installer/new OS
  has a different host key than the box's previous life.
