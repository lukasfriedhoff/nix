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

Console password for `root`/`nixos` is persisted via SOPS at:

`secrets/profiles/personal/servers/srv3/bootstrap-password.txt`

Decrypt it on any personal desktop with:

```bash
sops -d secrets/profiles/personal/servers/srv3/bootstrap-password.txt
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
- Ceph bootstrap daemons survive reboot on NixOS by re-installing runtime cephadm units (`/run/systemd/system`) on boot
- Ceph helper units probe monitors via `v2` endpoint only (no stale `v1` fallback)

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

If SSH authenticates but then hangs (no session channel), use this recovery path:

1. On hypervisor, verify VM state and capture screen:

```bash
ssh srv4 'virsh --connect qemu:///system dominfo srv3'
ssh srv4 'virsh --connect qemu:///system screenshot srv3 /tmp/srv3-screen.png'
```

2. If VM is stuck in shutdown/reboot loop, force-cycle it:

```bash
ssh srv4 'virsh --connect qemu:///system destroy srv3; sleep 2; virsh --connect qemu:///system start srv3'
```

3. Unlock first boot again when initrd SSH (`:2222`) comes up:

```bash
scripts/homelab/unlock.sh srv3 \
  --target root@10.1.30.25 \
  --port 2222 \
  --identity ~/.ssh/personal/srv3-personal-mgmt
```

## 10. Issues Seen In Practice And Workarounds

### ISO / boot issues

- Symptom: repeated `Failed unmounting /iso` and SquashFS read errors on console during shutdown/reboot.
- Cause: installer media/boot order mismatch while switching from ISO to installed disk.
- Workaround:

```bash
# On hypervisor
virsh --connect qemu:///system change-media srv3 sda --eject --config --live || true
virsh --connect qemu:///system reboot srv3
virsh --connect qemu:///system dumpxml srv3 | rg "<boot dev=|device='cdrom'|<source file="
```

Ensure disk boot is preferred after install; keep ISO attached only while installer is needed.

### SSH accepted key but session unhealthy

- Symptom: SSH key is accepted but session hangs or exits unexpectedly.
- Check:

```bash
ssh -vvv -i ~/.ssh/personal/srv3-personal-mgmt root@<SRV3_IP> 'echo ok'
ssh root@<SRV3_IP> 'systemctl status sshd systemd-logind --no-pager -l'
ssh root@<SRV3_IP> 'journalctl -b -u sshd -u systemd-logind --no-pager -l -n 200'
```

- Recovery path if normal SSH is blocked:
  - Use libvirt serial console first.
  - If required, stop VM, mount root disk on hypervisor, inject management key into `/root/.ssh/authorized_keys`, boot again.

### Ceph OSD provisioning failed on recycled disks

- Symptom: `ceph-volume-osd-create.service` fails with `RuntimeError: Device /dev/vdc has a filesystem`.
- Cause: old signatures/LVM metadata on ceph data disks from prior runs.
- Workaround:

```bash
ssh srv3 '
for d in /dev/vdc /dev/vdd /dev/vde; do
  sgdisk --zap-all "$d" || true
  wipefs -a "$d" || true
done
systemctl restart ceph-volume-osd-create.service
'
```

Only run disk zapping for explicit reprovisioning.

### Ceph OSD starts but fails opening `block` with `Operation not permitted`

- Symptom: `ceph-osd@1` fails with repeated:
  - `bdev(... /var/lib/ceph/osd/ceph-1/block) open stat got: (1) Operation not permitted`
  - `unable to mount object store`
- Cause: OSD metadata exists in LVM, but `/var/lib/ceph/osd/ceph-1/block` symlink is missing or stale.
- Workaround:

```bash
ssh srv3 '
ceph-volume lvm activate --bluestore 1 d18bb6c5-56d3-465a-b693-53a717d6ebdf || true
ln -sf /dev/mapper/YCD9eU-bei4-BQRS-dJuV-Sj5G-Ygbl-nB7Kxj /var/lib/ceph/osd/ceph-1/block
chown -h ceph:ceph /var/lib/ceph/osd/ceph-1/block
systemctl reset-failed ceph-osd@1
systemctl restart ceph-osd@1
systemctl --no-pager -l status ceph-osd@1
'
```

On NixOS, `ceph-volume lvm activate` may print an expected warning when trying to `systemctl enable` a generated unit under read-only `/etc`; OSD activation is still usable when the `block` link is corrected and `ceph-osd@1` is restarted.

### Ceph mgr unit mismatch (missing auth for stale daemon id)

- Symptom:
  - `ceph-...@mgr.srv3.xddbkj.service` fails with `failed to fetch mon config`
  - `ceph auth get mgr.srv3.xddbkj` returns `ENOENT`
- Cause: stale mgr daemon id/unit exists without corresponding auth entry.
- Workaround: run the valid mgr daemon (`mgr.srv3.dvecgx`) and clean stale mgr containers.

```bash
ssh srv3 '
systemctl stop ceph-5bb51195-8104-49cb-ad7c-a7cb6a7bfb1c@mgr.srv3.xddbkj.service || true
systemctl stop ceph-5bb51195-8104-49cb-ad7c-a7cb6a7bfb1c@mgr.srv3.dvecgx.service || true
podman ps -a --format "{{.Names}}" | grep -E "mgr-srv3-(xddbkj|dvecgx)" | xargs -r podman rm -f
systemctl reset-failed ceph-5bb51195-8104-49cb-ad7c-a7cb6a7bfb1c@mgr.srv3.dvecgx.service || true
systemctl start ceph-5bb51195-8104-49cb-ad7c-a7cb6a7bfb1c@mgr.srv3.dvecgx.service
systemctl --no-pager -l status ceph-5bb51195-8104-49cb-ad7c-a7cb6a7bfb1c@mgr.srv3.dvecgx.service
'
```

### Stale `osd.0` after reprovision

- Symptom: `ceph-osd@0.service` remains failed after migrating to OSDs `1..3`.
- Workaround:
  - If Ceph CLI is responsive, purge stale OSD entry:

```bash
ssh srv3 'ceph osd purge 0 --yes-i-really-mean-it'
```

  - If CLI is temporarily unresponsive, at least clear local failed unit state:

```bash
ssh srv3 'systemctl reset-failed ceph-osd@0'
```

### Flux bootstrap timing failure

- Symptom: `flux-gitops.service` fails with `TLS handshake timeout` to `https://127.0.0.1:6443/api`.
- Cause: k3s API not fully ready during first bootstrap attempt.
- Workaround:

```bash
ssh srv3 'systemctl restart flux-gitops.service'
ssh srv3 'comin fetch'
ssh srv3 'journalctl -u flux-gitops.service -n 120 --no-pager -l'
```

If direct SSH exec to `srv3` is flaky while this is happening, run the same commands via `srv4` as a jump host with the `srv3` management key copied to a temporary file on `srv4`.

### DNS not ready for unlock host alias

- Symptom: `unlock-srv3` name does not resolve during first boot unlock.
- Workaround: use lease fallback path already implemented in `scripts/homelab/unlock.sh`, or set explicit target:

```bash
scripts/homelab/unlock.sh srv3 \
  --target root@<LEASE_IP> \
  --port 2222 \
  --identity ~/.ssh/personal/srv3-personal-mgmt
```

### Flake build misses newly created secret file

- Symptom: build error `path .../bootstrap-password.txt does not exist`.
- Cause: new secret file exists locally but is untracked, so it is not part of flake source copy.
- Workaround:

```bash
git add secrets/profiles/personal/servers/srv3/bootstrap-password.txt
nix build .#nixosConfigurations.srv3.config.system.build.toplevel
```
