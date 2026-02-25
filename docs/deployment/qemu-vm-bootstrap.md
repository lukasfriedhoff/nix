# QEMU VM Bootstrap

This repo now includes `scripts/vms/new-qemu-vm.sh` to create libvirt/QEMU VMs.

## What the script does

- Creates and defines a VM using `virt-install` + `virsh`.
- Defaults to local libvirt: `qemu:///system`.
- Supports remote libvirt over SSH (`qemu+ssh://.../system`).
- Defaults to machine type `q35` and UEFI firmware.
- Supports two modes:
  - `cloud`: cloud image + cloud-init seed ISO.
  - `iso`: installer ISO boot.

## Quick usage

```bash
scripts/vms/new-qemu-vm.sh --help
```

## Example 1: Ubuntu cloud image with cloud-init

Example cloud-init files are provided under:

- `docs/examples/cloud-init/ubuntu/user-data.yaml`
- `docs/examples/cloud-init/ubuntu/meta-data.yaml`
- `docs/examples/cloud-init/ubuntu/network-config.yaml`

Create a local VM:

```bash
scripts/vms/new-qemu-vm.sh \
  --name ubuntu-dev-01 \
  --mode cloud \
  --image https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img \
  --memory 4096 \
  --vcpus 4 \
  --disk-size 60 \
  --user-data docs/examples/cloud-init/ubuntu/user-data.yaml \
  --meta-data docs/examples/cloud-init/ubuntu/meta-data.yaml \
  --network-config docs/examples/cloud-init/ubuntu/network-config.yaml
```

Create the same VM on a remote libvirt host over SSH:

```bash
scripts/vms/new-qemu-vm.sh \
  --remote root@srv1.lab.h4xx.io \
  --name ubuntu-ci-01 \
  --mode cloud \
  --image https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img \
  --memory 4096 \
  --vcpus 4
```

## Example 2: NixOS minimal installer VM, then provision with repo scripts

1. Create host files/secrets in this repo first (example host `srv3`):

```bash
scripts/homelab/new-host.sh \
  --host srv3 \
  --fqdn srv3.lab.h4xx.io \
  --root-disk-id virtio-srv3-root \
  --update-flake
```

2. Boot a NixOS minimal installer VM:

```bash
scripts/vms/new-qemu-vm.sh \
  --name srv3 \
  --mode iso \
  --iso https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso \
  --memory 4096 \
  --vcpus 4 \
  --disk-size 80 \
  --disk-serial srv3-root
```

3. In the installer, set console passwords:

```bash
passwd root
passwd nixos
```

4. Add the generated management key to installer `authorized_keys`:

```bash
installer_ip="<installer-ip>"
pub="secrets/profiles/personal/servers/srv3/ssh/srv3-personal-mgmt.pub"

scp "$pub" root@"$installer_ip":/tmp/mgmt.pub
ssh root@"$installer_ip" "mkdir -p /root/.ssh && cat /tmp/mgmt.pub >> /root/.ssh/authorized_keys"
```

5. Run unattended install with your existing wrapper:

```bash
scripts/servers/deploy-from-iso.sh \
  srv3 \
  root@<installer-ip> \
  --luks-secret secrets/profiles/personal/shared/luks/srv3.txt
```

6. Verify first boot and comin pull-mode:

```bash
ssh srv3
sudo systemctl status comin.service
```

## Notes

- `--force` will undefine/recreate an existing domain and overwrite disk/seed files.
- In `cloud` mode, `--disk-format qcow2` is required (overlay disk from base image).
- If you use `--bridge`, it is used instead of `--network`.
