# QEMU VM Bootstrap

This repo now includes `scripts/vms/new-qemu-vm.sh` to create libvirt/QEMU VMs.

For the full `srv4` multi-VLAN, multi-pool `srv3` walkthrough, use:
- `docs/deployment/srv3-demo-vm.md`

## What the script does

- Creates and defines a VM using `virt-install` + `virsh`.
- Defaults to local libvirt: `qemu:///system`.
- Supports remote libvirt over SSH (`qemu+ssh://.../system`).
- Defaults to machine type `q35` and UEFI firmware.
- Supports three modes:
  - `cloud`: cloud image + cloud-init seed ISO.
  - `iso`: installer ISO boot.
  - `netboot`: installer kernel+initrd + explicit kernel args.

## Quick usage

```bash
scripts/vms/new-qemu-vm.sh --help
```

## Installer URL status (validated on February 25, 2026)

### Ubuntu

- Netboot artifact exists:
  - `https://releases.ubuntu.com/24.04/ubuntu-24.04.3-netboot-amd64.tar.gz`
- Netboot kernel/initrd URLs exist:
  - `https://releases.ubuntu.com/24.04/netboot/amd64/linux`
  - `https://releases.ubuntu.com/24.04/netboot/amd64/initrd`
- Live server ISO exists (usable directly with this script):
  - `https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso`

How to use with `new-qemu-vm.sh`:

```bash
scripts/vms/new-qemu-vm.sh \
  --name ubuntu-installer-01 \
  --mode iso \
  --iso https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso
```

The Ubuntu netboot tarball is not an ISO, so `--mode iso` rejects it.
Use `--mode netboot` instead:

```bash
scripts/vms/new-qemu-vm.sh \
  --name ubuntu-netboot-01 \
  --mode netboot \
  --kernel https://releases.ubuntu.com/24.04/netboot/amd64/linux \
  --initrd https://releases.ubuntu.com/24.04/netboot/amd64/initrd \
  --kernel-args "ip=dhcp url=https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso autoinstall ds=nocloud-net;s=http://10.0.0.1/cloud-init/"
```

You can also extract the tarball and pass local paths:

```bash
tar -xzf ubuntu-24.04.3-netboot-amd64.tar.gz -C /tmp/ubuntu-netboot

scripts/vms/new-qemu-vm.sh \
  --name ubuntu-netboot-local-01 \
  --mode netboot \
  --kernel /tmp/ubuntu-netboot/amd64/linux \
  --initrd /tmp/ubuntu-netboot/amd64/initrd \
  --kernel-args "ip=dhcp url=https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso"
```

### NixOS

- Channel ISO artifacts exist:
  - `https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso`
  - `https://channels.nixos.org/nixos-unstable/latest-nixos-graphical-x86_64-linux.iso`
- Common netboot/kexec-style channel artifacts were checked and not found (404), e.g.:
  - `latest-nixos-netboot-x86_64-linux.tar.gz`
  - `latest-nixos-netboot-x86_64-linux.tar.xz`
  - `latest-nixos-kexec-x86_64-linux.tar.gz`

How to use with `new-qemu-vm.sh`:

```bash
scripts/vms/new-qemu-vm.sh \
  --name nixos-installer-01 \
  --mode iso \
  --iso https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso
```

For NixOS netboot, follow the wiki approach and build kernel/initrd from
`installer/netboot/netboot-minimal.nix`, then pass them to `--mode netboot`:

```bash
tmp_cfg="$(mktemp)"
cat > "$tmp_cfg" <<'NIX'
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/netboot/netboot-minimal.nix") ];
}
NIX

kernel_drv="$(nix-build '<nixpkgs/nixos>' -A config.system.build.kernel -I nixos-config="$tmp_cfg")"
initrd_drv="$(nix-build '<nixpkgs/nixos>' -A config.system.build.netbootRamdisk -I nixos-config="$tmp_cfg")"
toplevel_drv="$(nix-build '<nixpkgs/nixos>' -A config.system.build.toplevel -I nixos-config="$tmp_cfg")"

scripts/vms/new-qemu-vm.sh \
  --name nixos-netboot-01 \
  --mode netboot \
  --kernel "${kernel_drv}/bzImage" \
  --initrd "${initrd_drv}/initrd" \
  --kernel-args "init=${toplevel_drv}/init loglevel=4"
```

Reference:
- `https://wiki.nixos.org/wiki/Netboot`

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

## Example 2: Local srv3-style VM bootstrap (tested flow)

This is the runbook to reuse when creating a local homelab VM with a root disk,
dedicated swap disk, and additional Ceph data disks.

1. Create/update host files in this repo first:

```bash
scripts/homelab/new-host.sh \
  --host srv3 \
  --fqdn srv3.lab.h4xx.io \
  --root-disk-id virtio-srv3-root \
  --allow-existing \
  --update-flake
```

2. Boot the VM from your prebuilt ISO with management key baked in
   (`artifacts/iso/nixos-minimal-ci-ssh.iso` in this repo):

```bash
scripts/vms/new-qemu-vm.sh \
  --name srv3 \
  --mode iso \
  --iso artifacts/iso/nixos-minimal-ci-ssh.iso \
  --libosinfo-os-id http://nixos.org/nixos/unstable \
  --memory 16384 \
  --vcpus 6 \
  --disk-size 100 \
  --disk-serial srv3-root \
  --extra-disk 20:srv3-swap \
  --extra-disk 50:srv3-ceph1 \
  --extra-disk 50:srv3-ceph2 \
  --extra-disk 50:srv3-ceph3 \
  --wait 0
```

By default, `new-qemu-vm.sh` now defines:
- 2 serial consoles (`serial0`, `serial1`)
- VNC graphics (`--graphics vnc`)

Use all three views during recovery:

```bash
virsh --connect qemu:///system console srv3 --devname serial0
virsh --connect qemu:///system console srv3 --devname serial1
virsh --connect qemu:///system domdisplay srv3
```

3. Get installer IP from local libvirt:

```bash
virsh --connect qemu:///system domifaddr srv3 --source lease
```

4. Deploy with the wrapper (defaults to `--phases disko,install,reboot`,
   so no kexec IP switch during install):

```bash
scripts/servers/deploy-from-iso.sh \
  srv3 \
  root@<installer-ip> \
  --identity ~/.ssh/personal/srv3-personal-mgmt \
  --ssh-option IdentitiesOnly=yes \
  --luks-secret secrets/profiles/personal/shared/luks/srv3.txt
```

5. First boot after install will wait for LUKS unlock (initrd SSH on `:2222`):

```bash
scripts/homelab/unlock.sh srv3
```

If `unlock-srv3` DNS is not resolvable yet, `unlock.sh` falls back to the local
libvirt lease IP for `srv3` automatically. Manual fallback is also possible:

```bash
scripts/homelab/unlock.sh srv3 \
  --target root@192.168.122.30 \
  --port 2222 \
  --identity ~/.ssh/personal/srv3-personal-mgmt \
  --ssh-option IdentitiesOnly=yes \
  --ssh-option StrictHostKeyChecking=no \
  --ssh-option UserKnownHostsFile=/dev/null
```

6. Verify disk layout and services:

```bash
ssh srv3 'lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,SERIAL'
ssh srv3 'cat /proc/swaps'
ssh srv3 'systemctl is-system-running || true'
ssh srv3 'systemctl --failed --no-pager'
```

Expected disk shape for this example:
- `vda` root 100G (`serial=srv3-root`)
- `vdb` swap 20G (`serial=srv3-swap`)
- `vdc/vdd/vde` Ceph disks 50G each (`serial=srv3-ceph1..3`)

## Notes

- `--force` will undefine/recreate an existing domain and overwrite disk/seed files.
- To fully clean a VM and leftover pool volumes, use `scripts/vms/remove-qemu-vm.sh --name <vm-name>`.
- In `cloud` mode, `--disk-format qcow2` is required (overlay disk from base image).
- `--extra-disk` lets you create/attach additional disks in one call so serial+format stay correct.
- In `iso` mode, the script defines boot order as `hd` first then `cdrom` (installer still boots on first run, but post-install reboot will prefer disk).
- If an older VM keeps rebooting into the installer ISO, eject media and reboot:
  ```bash
  virsh --connect qemu:///system change-media <name> sda --eject --live --config
  virsh --connect qemu:///system reboot <name>
  ```
- In `netboot` mode on `qemu:///system`, libvirt stages kernel/initrd under `/var/lib/libvirt/boot`.
  If that directory is missing, create it on the libvirt host (for example `sudo mkdir -p /var/lib/libvirt/boot`).
- If you use `--bridge`, it is used instead of `--network`.
- If Ceph units fail with “cluster with the same fsid already exists”, the Ceph disks still contain old cluster state and must be reprovisioned per `docs/services/ceph.md`.
