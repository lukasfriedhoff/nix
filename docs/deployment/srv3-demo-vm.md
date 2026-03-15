# srv3 Demo VM

This runbook recreates `srv3` as a multi-disk libvirt VM on `srv4`, deploys NixOS from ISO, unlocks LUKS over initrd SSH, and verifies pull-based rollout (`comin`) plus Kubernetes/Flux status.

## 1. Cleanup (safe repeatable start)

From your local repo:

```bash
scripts/vms/remove-qemu-vm.sh --name srv3 --pool nvmepool --pool ssdpool --pool images --dry-run
scripts/vms/remove-qemu-vm.sh --name srv3 --pool nvmepool --pool ssdpool --pool images
```

On `srv4`, confirm no leftovers:

```bash
ssh srv4 '
virsh --connect qemu:///system list --all | grep -E "srv3|Name" || true
virsh --connect qemu:///system vol-list nvmepool | grep srv3 || true
virsh --connect qemu:///system vol-list ssdpool | grep srv3 || true
'
```

## 2. Prepare host config + resources

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
  --mon-ip 10.1.30.25 \
  --root-disk-id virtio-srv3-root \
  --swap-disk-id virtio-srv3-swap \
  --ceph-disk-ids virtio-srv3-ceph1,virtio-srv3-ceph2,virtio-srv3-ceph3
```

## 3. Create disks and VM on srv4

This keeps:
- root/swap on `nvmepool`
- ceph disks on `ssdpool`
- 3 NICs on VLAN 30/20/40 bridges
- VNC + 2 serial consoles
- libosinfo metadata for NixOS unstable

```bash
ssh srv4 'bash -seuo pipefail' <<'EOF'
# Create/replace logical volumes used by libvirt pools
for spec in srv3-root:100G srv3-swap:20G; do
  name="${spec%:*}"; size="${spec#*:}"
  virsh --connect qemu:///system vol-delete "${name}" nvmepool >/dev/null 2>&1 || true
  virsh --connect qemu:///system vol-create-as nvmepool "${name}" "${size}" --format raw
done
for spec in srv3-ceph1:50G srv3-ceph2:50G srv3-ceph3:50G; do
  name="${spec%:*}"; size="${spec#*:}"
  virsh --connect qemu:///system vol-delete "${name}" ssdpool >/dev/null 2>&1 || true
  virsh --connect qemu:///system vol-create-as ssdpool "${name}" "${size}" --format raw
done

# Recreate domain XML
virsh --connect qemu:///system destroy srv3 >/dev/null 2>&1 || true
virsh --connect qemu:///system undefine srv3 --nvram >/dev/null 2>&1 || true
virsh --connect qemu:///system undefine srv3 >/dev/null 2>&1 || true

raw="$(mktemp)"
xml="$(mktemp)"

virt-install \
  --connect qemu:///system \
  --name srv3 \
  --memory 4096 \
  --vcpus 2 \
  --machine q35 \
  --osinfo generic \
  --disk vol=nvmepool/srv3-root,bus=virtio,serial=srv3-root \
  --disk vol=nvmepool/srv3-swap,bus=virtio,serial=srv3-swap \
  --disk vol=ssdpool/srv3-ceph1,bus=virtio,serial=srv3-ceph1 \
  --disk vol=ssdpool/srv3-ceph2,bus=virtio,serial=srv3-ceph2 \
  --disk vol=ssdpool/srv3-ceph3,bus=virtio,serial=srv3-ceph3 \
  --network bridge=br-vlan30,model=virtio,mac=52:54:00:0a:dd:ea \
  --network bridge=br-vlan20,model=virtio,mac=52:54:00:ea:a2:2c \
  --network bridge=br-vlan40,model=virtio,mac=52:54:00:a5:7a:cc \
  --graphics vnc,listen=127.0.0.1 \
  --console pty,target.type=serial,target.port=0 \
  --console pty,target.type=serial,target.port=1 \
  --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no,firmware.feature1.name=enrolled-keys,firmware.feature1.enabled=no \
  --cdrom /home/lukasf/images/nixos-minimal-ci-ssh.iso \
  --noautoconsole \
  --wait 0 \
  --print-xml > "$raw"

python3 - "$raw" "$xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
raw, out = sys.argv[1], sys.argv[2]
root = ET.parse(raw).getroot()

ns_uri = "http://libosinfo.org/xmlns/libvirt/domain/1.0"
ET.register_namespace("libosinfo", ns_uri)

for elem in list(root.findall("metadata")):
    root.remove(elem)

metadata = ET.Element("metadata")
libosinfo = ET.SubElement(metadata, f"{{{ns_uri}}}libosinfo")
ET.SubElement(libosinfo, f"{{{ns_uri}}}os", {"id": "http://nixos.org/nixos/unstable"})
root.append(metadata)

ET.ElementTree(root).write(out, encoding="unicode")
PY

virsh --connect qemu:///system define "$xml"
virsh --connect qemu:///system start srv3
virsh --connect qemu:///system domdisplay srv3
virsh --connect qemu:///system dumpxml srv3 | sed -n '/<metadata>/,/<\/metadata>/p'
EOF
```

## 4. Find installer IP and deploy

Check VM lease/IP:

```bash
ssh srv4 'virsh --connect qemu:///system domifaddr srv3 --source lease || true'
```

Deploy from ISO (installer shell access via CI key):

```bash
scripts/servers/deploy-from-iso.sh \
  srv3 \
  root@<INSTALLER_IP> \
  --identity ~/.ssh/personal/ci \
  --ssh-option IdentitiesOnly=yes \
  --luks-secret secrets/profiles/personal/shared/luks/srv3.txt
```

Notes:
- `deploy-from-iso.sh` now strips trailing CR/LF from decrypted LUKS secrets before passing them to disko.
- `unlock.sh` now also strips trailing CR/LF before writing `/crypt-ramfs/passphrase`.

## 5. First boot unlock (initrd SSH)

Normal path:

```bash
scripts/homelab/unlock.sh srv3 --identity ~/.ssh/personal/srv3-personal-mgmt
```

If DNS is not ready, use explicit target/port:

```bash
scripts/homelab/unlock.sh srv3 \
  --target root@<INITRD_IP> \
  --port 2222 \
  --identity ~/.ssh/personal/srv3-personal-mgmt \
  --ssh-option IdentitiesOnly=yes \
  --ssh-option StrictHostKeyChecking=no \
  --ssh-option UserKnownHostsFile=/dev/null
```

## 6. Verify host and comin

```bash
ssh -i ~/.ssh/personal/srv3-personal-mgmt -o IdentitiesOnly=yes root@10.1.30.25 '
hostnamectl --static
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,SERIAL
cat /proc/swaps
systemctl --failed --no-pager
systemctl status comin.service --no-pager -n 80
journalctl -u comin.service --no-pager -n 120
'
```

## 7. Kubernetes and Flux checks

```bash
ssh -i ~/.ssh/personal/srv3-personal-mgmt -o IdentitiesOnly=yes root@10.1.30.25 '
systemctl status k3s.service --no-pager -n 120 || true
kubectl get nodes -o wide || true
kubectl get pods -A || true
kubectl get kustomizations -A || true
kubectl get helmreleases -A || true
'
```

If Flux CRDs are not available yet, wait for bootstrap/rollout and re-run checks.

## 8. Recovery commands

Check console paths:

```bash
ssh srv4 '
virsh --connect qemu:///system domdisplay srv3
virsh --connect qemu:///system ttyconsole srv3
virsh --connect qemu:///system dumpxml srv3 | sed -n "/<serial /,/<\\/serial>/p"
'
```

Eject ISO after install and reboot:

```bash
ssh srv4 '
virsh --connect qemu:///system change-media srv3 sda --eject --live --config || true
virsh --connect qemu:///system reboot srv3
'
```

Hard power cycle:

```bash
ssh srv4 '
virsh --connect qemu:///system destroy srv3 || true
sleep 2
virsh --connect qemu:///system start srv3
'
```

