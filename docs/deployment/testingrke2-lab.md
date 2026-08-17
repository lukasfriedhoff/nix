# Testing RKE2 VM Lab

`testingrke2` is a three-node, highly available RKE2 cluster running as local
libvirt VMs on `tux-h4xx-01`. It is intended to validate the migration from k3s
to RKE2 without changing the existing testing cluster.

## Topology

| Node | Address | MAC | RKE2 role | Keepalived priority |
|------|---------|-----|-----------|----------------------|
| `testingrke2-01` | `192.168.124.11` | `52:54:00:72:6b:11` | Server and Flux bootstrap | 130 |
| `testingrke2-02` | `192.168.124.12` | `52:54:00:72:6b:12` | Server | 120 |
| `testingrke2-03` | `192.168.124.13` | `52:54:00:72:6b:13` | Server | 110 |

- API and registration virtual IP: `192.168.124.10`
- Libvirt network: `testingrke2` on `virbr-rke2`
- VM resources: 4 vCPU, 8 GiB RAM, 80 GiB encrypted root, and one sparse
  500 GiB Longhorn disk per node
- RKE2 CNI: Canal
- Bundled RKE2 ingress: disabled; the GitOps stack installs the shared ingress
  implementation
- Storage: Longhorn using `/var/lib/longhorn-disk1`

The VM definitions live under `hosts/homelab/testingrke2*`. Reusable
distribution, joining, Longhorn, Flux, and keepalived behavior lives in
`modules/features/homelab/kubernetes/nixos.nix`.

## GitOps Overlay

The Flux cluster repository contains `overlays/testingrke2`. It layers on top
of `overlays/testing-srv3`, so testing application changes automatically flow
into the RKE2 lab without duplicating the full testing overlay.

The first bootstrap deliberately suspends:

- Cloudflare Tunnel and external-dns, to avoid competing for public records
- Media, navigation, Moonlight, and Nix build/cache workloads
- Nextcloud, Immich, Logday, Matrix, and Forgejo until their cluster-specific
  OIDC, storage, and backup settings are reviewed

The resources remain in the rendered copy and can be enabled one group at a
time by overriding the corresponding `*_suspend` value. The overlay removes
Ceph resources and adds one Longhorn `Node` resource for each VM.

For the initial lab only, the overlay reuses the encrypted
`overlays/testing-srv3/secrets` resources. The Flux SOPS key on
`testingrke2-01` is therefore the same key used to decrypt the testing
overlay. Do not enable stateful applications until their backup generations,
hostnames, and storage targets have been reviewed.

Before bootstrapping Flux, publish the Nix changes on `develop` (CI promotes
them to the `deploy` branch that comin tracks once checks pass) and the
Flux-cluster changes on `testing`. Flux cannot reconcile an uncommitted local
overlay.

## Prerequisites

- `artifacts/iso/nixos-minimal-ci-ssh.iso` exists, or
  `TESTINGRKE2_INSTALLER_ISO` points to another SSH-enabled NixOS installer
- The installer SSH identity is available through
  `TESTINGRKE2_INSTALLER_IDENTITY` or one of the fallback paths printed by
  `scripts/vms/testingrke2-lab.sh help`
- `/data/libvirt/images/testingrke2` has enough real free space for the sparse
  disks as they grow
- `virsh`, `virt-install`, `sops`, `nixos-anywhere`, `kubectl`, and `flux` are
  available
- `tux-h4xx-01` has been rebuilt with the KVM feature enabled. The feature
  enables libvirt guest-name NSS resolution, so the generated
  `testingrke2-*` and `unlock-testingrke2-*` SSH aliases do not require
  private guest addresses in Git.

## Validate Before Creating VMs

Run the local topology checks:

```bash
scripts/vms/test-testingrke2-lab.sh
```

In the Flux cluster repository, run:

```bash
scripts/verify-testingrke2-overlay.sh
```

The RKE2 module also has a NixOS VM test exposed as:

```bash
nix build .#checks.x86_64-linux.homelab-rke2-module
```

## Bootstrap

The complete flow is:

```bash
scripts/vms/testingrke2-lab.sh bootstrap
```

For controlled execution, run each phase separately:

```bash
scripts/vms/testingrke2-lab.sh network
scripts/vms/testingrke2-lab.sh create
scripts/vms/testingrke2-lab.sh authorize all
scripts/vms/testingrke2-lab.sh deploy testingrke2-01
scripts/vms/testingrke2-lab.sh deploy testingrke2-02
scripts/vms/testingrke2-lab.sh deploy testingrke2-03
scripts/vms/testingrke2-lab.sh kubeconfig
scripts/vms/testingrke2-lab.sh status
```

The kubeconfig is written to `~/.kube/testingrke2.yaml` by default and points
at the virtual IP:

```bash
KUBECONFIG=~/.kube/testingrke2.yaml kubectl get nodes -o wide
KUBECONFIG=~/.kube/testingrke2.yaml flux get all -A
```

## Day-Two Operations

```bash
scripts/vms/testingrke2-lab.sh start
scripts/vms/testingrke2-lab.sh stop
scripts/vms/testingrke2-lab.sh status
```

To remove the complete lab, including its VM disks and libvirt network:

```bash
scripts/vms/testingrke2-lab.sh destroy --confirm
```

This is destructive. Longhorn data in the VM disks is not retained.

## Acceptance Checks

After bootstrap:

```bash
KUBECONFIG=~/.kube/testingrke2.yaml kubectl get nodes
KUBECONFIG=~/.kube/testingrke2.yaml kubectl -n kube-system get pods
KUBECONFIG=~/.kube/testingrke2.yaml kubectl -n longhorn-system get nodes.longhorn.io
KUBECONFIG=~/.kube/testingrke2.yaml kubectl -n flux-system get gitrepositories,kustomizations
curl --fail --insecure https://192.168.124.10:6443/readyz
```

Expected results:

- all three nodes are `Ready`
- the API remains reachable while any one VM is stopped
- all three Longhorn nodes expose `longhorn-disk1`
- Flux tracks branch `testing` and path `./overlays/testingrke2`
- Cloudflare Tunnel, external-dns, and the guarded stateful workloads remain
  suspended until explicitly enabled
