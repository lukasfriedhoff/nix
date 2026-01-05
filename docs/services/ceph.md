# Ceph (cephadm) module

This repo ships a minimal cephadm-based module at `modules/nixos/services/ceph.nix`.
It bootstraps a cluster (if none exists), optionally sets the public network, and can
auto-provision OSDs from a device list.

## Quick start (single-node)

```nix
{
  lukasf.ceph = {
    enable = true;
    bootstrap = {
      monIp = "10.1.30.5";
      publicNetwork = "10.1.30.0/24";
      singleHostDefaults = true;
      skipDashboard = true;
    };
    osd = {
      devices = [
        "/dev/disk/by-id/ata-..."
        "/dev/disk/by-id/ata-..."
      ];
      autoProvision = true;
      method = "raw";
      encrypted = true;
    };
  };
}
```

Notes:
- `bootstrap.monIp` is required when bootstrap is enabled.
- `openFirewall` defaults to true (opens 3300/6789 and 6800-7300).
- `osd.zapDevices = true` will **wipe disks** before provisioning.

## How the module works

- `cephadm-bootstrap` runs once if `/etc/ceph/ceph.conf` does not exist.
- `cephadm-public-network` sets `mon public_network` after bootstrap when configured.
- `cephadm-osd` adds OSDs for configured devices using `ceph orch`.
- `cephadm` is wrapped to inject python deps and a systemctl shim.

## Options summary

`lukasf.ceph` options:
- `enable` (bool): enable the module.
- `package` (pkg): ceph package.
- `openFirewall` (bool, default true): open Ceph ports.

`lukasf.ceph.bootstrap`:
- `enable` (bool, default true): run bootstrap if no cluster exists.
- `monIp` (string, required when bootstrap enabled): monitor IP.
- `fsid` (string|null): optional cluster FSID.
- `publicNetwork` (string|null): CIDR(s) for public network.
- `clusterNetwork` (string|null): CIDR(s) for cluster network.
- `singleHostDefaults` (bool, default true): replication size=1 defaults.
- `skipDashboard` (bool, default true): skip dashboard deploy.
- `extraArgs` (list of strings): extra args to `cephadm bootstrap`.

`lukasf.ceph.osd`:
- `host` (string): ceph orch host name used when adding OSDs.
- `devices` (list of strings): device paths to provision.
- `method` ("raw"|"lvm", default "raw").
- `encrypted` (bool, default true): attempt dm-crypt with `--dmcrypt`.
- `zapDevices` (bool, default false): wipe disks before provisioning.
- `autoProvision` (bool, default false): run OSD provisioning unit.

`lukasf.ceph.monUpdate`:
- `enable` (bool): update mon addresses in the monmap.
- `name` (string|null): mon name to update (single-mon auto if null).
- `address` (string|null): target mon IP address.
- `legacyAddress` (string|null): temporary legacy mon IP added to loopback during update.
- `legacyPrefixLength` (int, default 32): prefix for the temporary legacy IP.
- `v1Port` (int, default 6789): legacy port.
- `v2Port` (int, default 3300): v2 port.

`lukasf.ceph.client`:
- `enable` (bool): write a client `ceph.conf`.
- `clusterName` (string, default `ceph`): cluster name.
- `fsid` (string|null): optional FSID pin.
- `monHosts` (list of strings): monitor hosts/IPs for `mon_host`.
- `monPort` (int, default 3300): v2 monitor port.
- `publicNetwork` (string|null): optional public network CIDR(s).
- `confFile` (string, default `/etc/ceph/ceph.conf`): target config path.
- `extraConfig` (lines): extra config lines appended.

`lukasf.ceph.pools`:
- `name` (string): pool name.
- `application` (string, default `rbd`): pool application.
- `size` (int, default 3): replication size.
- `minSize` (int|null): minimum replication size.
- `pgNum` (int|null): PG count (optional).

Example:

```nix
lukasf.ceph.pools = [
  {
    name = "images";
    application = "rbd";
    size = 1;
    minSize = 1;
  }
  {
    name = "vmdisks";
    application = "rbd";
    size = 3;
    minSize = 2;
  }
];
```

## Adding storage (OSDs)

Update your device list and re-deploy.
Example (srv1):

```nix
lukasf.ceph.osd.devices = [
  "/dev/disk/by-id/ata-..."
  "/dev/disk/by-id/ata-..."
];
```

If disks contain partitions, set `osd.zapDevices = true` once to wipe them,
then revert it to `false` after OSDs are created.

## Topology-driven config

For homelab-style deployments you can centralize cluster and storage
definitions and assign host roles, then reference the data from host configs.

Example topology file:

```nix
{
  clusters = {
    homelab = {
      monIp = "10.1.30.12";
      monHosts = [ "srv1.lab.h4xx.io" ];
      monPort = 3300;
      publicNetwork = "10.1.30.0/24";
      bootstrap = {
        singleHostDefaults = true;
        skipDashboard = true;
      };
      pools = [
        { name = "images"; application = "rbd"; size = 1; minSize = 1; }
        { name = "vmdisks"; application = "rbd"; size = 3; minSize = 2; }
      ];
    };
  };
  hosts = {
    srv1 = {
      cluster = "homelab";
      roles = [ "bootstrap" "osd" ];
    };
  };
}
```

Host usage (excerpt):

```nix
let
  cephTopology = import ../../../resources/homelab/ceph.nix;
  cephHost = cephTopology.hosts.${hostName};
  cephCluster = cephTopology.clusters.${cephHost.cluster};
  hasRole = role: lib.elem role cephHost.roles;
in {
  lukasf.ceph.bootstrap.enable = hasRole "bootstrap";
  lukasf.ceph.bootstrap.monIp = cephCluster.monIp;
  lukasf.ceph.bootstrap.publicNetwork = cephCluster.publicNetwork;
  lukasf.ceph.pools = lib.optionals (hasRole "bootstrap") cephCluster.pools;
  lukasf.ceph.osd.autoProvision = hasRole "osd";
}
```

Client config (example):

```nix
let
  cephTopology = import ../../../resources/homelab/ceph.nix;
  cephCluster = cephTopology.clusters.homelab;
in {
  lukasf.ceph.client = {
    enable = true;
    monHosts = cephCluster.monHosts or [ cephCluster.monIp ];
    monPort = cephCluster.monPort or 3300;
    fsid = cephCluster.fsid or null;
  };
}
```

Monitor address update (single mon example):

```nix
lukasf.ceph.monUpdate = {
  enable = true;
  name = "srv1";
  address = "10.1.30.12";
  legacyAddress = "10.1.30.5";
};
```

## Adding additional nodes

This module only bootstraps and provisions OSDs on the node where it is enabled.
For additional hosts:

1) Enable cephadm tools by enabling the module on the host, but disable bootstrap:

```nix
lukasf.ceph = {
  enable = true;
  bootstrap.enable = false;
};
```

2) From any admin node:

```bash
cephadm shell -- ceph orch host add <hostname> <ip>
cephadm shell -- ceph orch host label add <hostname> _admin
```

3) Add OSDs on the new host by setting `lukasf.ceph.osd.devices` on that host
and `autoProvision = true`, or use:

```bash
cephadm shell -- ceph orch daemon add osd <host>:/dev/disk/by-id/...
```

## Monitoring and dashboards

The module does not deploy monitoring by default. Typical cephadm commands:

```bash
cephadm shell -- ceph orch apply prometheus
cephadm shell -- ceph orch apply grafana
cephadm shell -- ceph orch apply node-exporter
```

If you want the built-in dashboard, set `bootstrap.skipDashboard = false` and
expose it via your firewall/reverse-proxy.

## Accessing the cluster

### From the cluster node

Use the cephadm wrapper:

```bash
cephadm shell -- ceph -s
```

Config and admin keyring live at:
- `/etc/ceph/ceph.conf`
- `/etc/ceph/ceph.client.admin.keyring`

### From another host

Install `ceph` client tools and copy:
- `/etc/ceph/ceph.conf`
- an appropriate keyring (admin or a limited client key)

Then you can use `ceph`, `rbd`, or mount CephFS.

## Encryption

`osd.encrypted = true` attempts `--dmcrypt` during `ceph orch daemon add osd`.
Some ceph versions reject this flag for `orch daemon add osd`; the module will
retry without it. If you require encryption today, use a LUKS layer and pass the
`/dev/mapper/...` devices as OSD devices.

## Troubleshooting

- Service status: `systemctl status cephadm-bootstrap cephadm-public-network cephadm-osd`
- Logs: `journalctl -u cephadm-osd -n 200 --no-pager`
- Cluster status: `cephadm shell -- ceph -s`
