# srv3 Demo VM Runbook

This runbook recreates `srv3` as a demo VM, deploys NixOS from ISO, and verifies Ceph + k3s + Flux on first rollout.

## 1. Clean up old VM artifacts

Local libvirt:

```bash
scripts/vms/remove-qemu-vm.sh --name srv3 --pool default --pool tmp
```

Remote libvirt host (`srv4`) example:

```bash
ssh srv4 'virsh --connect qemu:///system destroy srv3 || true; virsh --connect qemu:///system undefine srv3 --nvram || true; virsh --connect qemu:///system undefine srv3 || true'
```

## 2. Create/refresh host config in this repo

```bash
scripts/homelab/new-host.sh \
  --host srv3 \
  --fqdn srv3.lab.h4xx.io \
  --root-disk-id virtio-srv3-root \
  --allow-existing \
  --update-flake

scripts/homelab/add-testing-resources.sh \
  --host srv3 \
  --fqdn srv3.lab.h4xx.io \
  --cluster testing \
  --mon-ip 192.168.122.57 \
  --root-disk-id virtio-srv3-root \
  --swap-disk-id virtio-srv3-swap \
  --ceph-disk-ids virtio-srv3-ceph1,virtio-srv3-ceph2,virtio-srv3-ceph3

nix fmt
```

## 3. Create the VM

Local helper script (single host libvirt):

```bash
scripts/vms/new-qemu-vm.sh \
  --name srv3 \
  --mode iso \
  --disk-size 100 \
  --disk-serial srv3-root \
  --extra-disk 20:srv3-swap \
  --extra-disk 50:srv3-ceph1 \
  --extra-disk 50:srv3-ceph2 \
  --extra-disk 50:srv3-ceph3 \
  --iso https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso
```

If you run on `srv4`, keep these requirements:

- machine: `q35`, UEFI, secure boot disabled
- NICs on all required VLAN bridges (mgmt/server/storage)
- graphics enabled (VNC/SPICE) plus **two serial consoles** (`target.port=0` and `target.port=1`)
- include libosinfo metadata:

```xml
<metadata>
  <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
    <libosinfo:os id="http://nixos.org/nixos/unstable"/>
  </libosinfo:libosinfo>
</metadata>
```

## 4. Get installer IP and deploy from ISO

```bash
virsh --connect qemu:///system domifaddr srv3 --source lease
```

Deploy:

```bash
scripts/servers/deploy-from-iso.sh \
  srv3 root@<INSTALLER_IP> \
  --identity ~/.ssh/personal/ci \
  --ssh-option IdentitiesOnly=yes \
  --luks-secret secrets/profiles/personal/shared/luks/srv3.txt
```

If installer auth with management key fails initially, copy the public key into installer `authorized_keys` first, then rerun deploy.

## 5. First boot unlock and SSH validation

```bash
scripts/homelab/unlock.sh srv3 --identity ~/.ssh/personal/srv3-personal-mgmt

until ssh -i ~/.ssh/personal/srv3-personal-mgmt \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  root@<SRV3_IP> 'echo srv3-up'; do
  sleep 3
done
```

## 6. Trigger comin and verify rollout

```bash
ssh srv3 'comin fetch'
ssh srv3 'journalctl -u comin.service -n 120 --no-pager -l'
ssh srv3 'systemctl --failed --no-pager'
```

## 7. Validate Ceph, k3s, and Flux

```bash
ssh srv3 'ceph -s'
ssh srv3 'ceph osd tree'
ssh srv3 'k3s kubectl get nodes -o wide'
ssh srv3 'k3s kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A'
```

Expected after the fixes in this repo:

- Ceph: `HEALTH_OK`, OSDs `3 up, 3 in`
- k3s control plane: `Ready`
- Flux bootstrap chain (`namespaces`, `secrets`, `repositories`) reaches `Ready=True`

## 8. Known app-layer follow-up

If app-level Flux Kustomizations are not all ready (for example `traefik-app` CRD ordering issues), investigate in `flux-cluster` manifests. The `nix` repo side is now wired so:

- `flux-system/sops-age` is created automatically by bootstrap
- `srv3` uses a dedicated encrypted Flux decryption key (`secrets/profiles/personal/servers/srv3/flux-sops-age.key`)
- core bootstrap and Ceph/k3s rollout complete successfully

## 9. Useful recovery commands

```bash
# Force one more fetch/redeploy cycle
ssh srv3 'comin fetch'

# Reconcile Flux manually
ssh srv3 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; flux --namespace flux-system reconcile source git flux-cluster'
ssh srv3 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; flux --namespace flux-system reconcile kustomization testing --with-source'

# Serial console (local libvirt)
virsh --connect qemu:///system console srv3 --devname serial0
virsh --connect qemu:///system console srv3 --devname serial1
```
