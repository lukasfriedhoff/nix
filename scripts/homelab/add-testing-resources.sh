#!/usr/bin/env bash
# Add/update homelab resource entries for a testing Ceph/KVM host.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/homelab/add-testing-resources.sh [options]

Adds step-2 resource entries for recreating a srv3-style testing node:
  - resources/homelab/disks.nix
  - resources/homelab/ceph.nix (clusters + hosts maps)

Defaults match the previous srv3 setup:
  --host srv3
  --fqdn srv3.lab.h4xx.io
  --cluster testing
  --fsid 5bb51195-8104-49cb-ad7c-a7cb6a7bfb1c
  --mon-ip 192.168.122.41
  --public-network 192.168.122.0/24
  --secret-uuid 3ddfbba6-8046-4d3e-a18b-1f2542002865
  --root-disk-id virtio-srv3-root
  --swap-disk-id virtio-srv3-swap
  --ceph-disk-ids virtio-srv3-ceph1,virtio-srv3-ceph2,virtio-srv3-ceph3

Options:
  --host <name>
  --fqdn <fqdn>
  --cluster <name>
  --fsid <uuid>
  --mon-ip <ip>
  --mon-port <port>                (default: 3300)
  --public-network <cidr>
  --secret-uuid <uuid>
  --root-disk-id <disk-id>
  --swap-disk-id <disk-id>
  --ceph-disk-ids <id,id,id>
  --dry-run
  -h, --help

Example:
  scripts/homelab/add-testing-resources.sh
EOF
}

host="srv3"
fqdn="srv3.lab.h4xx.io"
cluster="testing"
fsid="5bb51195-8104-49cb-ad7c-a7cb6a7bfb1c"
mon_ip="192.168.122.41"
mon_port="3300"
public_network="192.168.122.0/24"
secret_uuid="3ddfbba6-8046-4d3e-a18b-1f2542002865"
root_disk_id="virtio-srv3-root"
swap_disk_id="virtio-srv3-swap"
ceph_disk_ids_csv="virtio-srv3-ceph1,virtio-srv3-ceph2,virtio-srv3-ceph3"
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) host="$2"; shift 2 ;;
    --fqdn) fqdn="$2"; shift 2 ;;
    --cluster) cluster="$2"; shift 2 ;;
    --fsid) fsid="$2"; shift 2 ;;
    --mon-ip) mon_ip="$2"; shift 2 ;;
    --mon-port) mon_port="$2"; shift 2 ;;
    --public-network) public_network="$2"; shift 2 ;;
    --secret-uuid) secret_uuid="$2"; shift 2 ;;
    --root-disk-id) root_disk_id="$2"; shift 2 ;;
    --swap-disk-id) swap_disk_id="$2"; shift 2 ;;
    --ceph-disk-ids) ceph_disk_ids_csv="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing required command: $1" >&2
    exit 2
  }
}

need_cmd git
need_cmd python3

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

disks_file="resources/homelab/disks.nix"
ceph_file="resources/homelab/ceph.nix"

[[ -f "$disks_file" ]] || { echo "error: missing ${disks_file}" >&2; exit 3; }
[[ -f "$ceph_file" ]] || { echo "error: missing ${ceph_file}" >&2; exit 3; }

echo ">> Adding resource entries for host=${host} cluster=${cluster}"
if [[ "$dry_run" == true ]]; then
  echo ">> Dry-run mode: files will not be changed"
fi

python3 - "$disks_file" "$ceph_file" "$host" "$fqdn" "$cluster" "$fsid" "$mon_ip" "$mon_port" "$public_network" "$secret_uuid" "$root_disk_id" "$swap_disk_id" "$ceph_disk_ids_csv" "$dry_run" <<'PY'
import re
import sys
from pathlib import Path

(
    disks_path_s,
    ceph_path_s,
    host,
    fqdn,
    cluster,
    fsid,
    mon_ip,
    mon_port,
    public_network,
    secret_uuid,
    root_disk_id,
    swap_disk_id,
    ceph_disk_ids_csv,
    dry_run_s,
) = sys.argv[1:]

dry_run = dry_run_s.lower() == "true"

disks_path = Path(disks_path_s)
ceph_path = Path(ceph_path_s)
ceph_disk_ids = [x.strip() for x in ceph_disk_ids_csv.split(",") if x.strip()]
if not ceph_disk_ids:
    sys.exit("error: --ceph-disk-ids must contain at least one disk id")


def find_block_bounds(src: str, marker: str):
    marker_pos = src.find(marker)
    if marker_pos < 0:
        raise RuntimeError(f"missing marker: {marker}")
    open_pos = src.find("{", marker_pos)
    if open_pos < 0:
        raise RuntimeError(f"missing '{{' after marker: {marker}")
    depth = 0
    for i in range(open_pos, len(src)):
        ch = src[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return open_pos, i
    raise RuntimeError(f"unbalanced braces around marker: {marker}")


def has_attr_block(src: str, name: str) -> bool:
    return re.search(rf'^\s*{re.escape(name)}\s*=\s*\{{', src, flags=re.MULTILINE) is not None


def has_quoted_attr_block(src: str, name: str) -> bool:
    return re.search(rf'^\s*"{re.escape(name)}"\s*=\s*\{{', src, flags=re.MULTILINE) is not None


# Patch disks.nix
disks_src = disks_path.read_text()
root_open, root_close = find_block_bounds(disks_src, "{")
disks_body = disks_src[root_open + 1 : root_close]

added_disks = []

def disk_entry(disk_id: str, purpose: str) -> str:
    return (
        f'  "{disk_id}" = {{\n'
        f'    host = "{host}";\n'
        f'    purpose = "{purpose}";\n'
        f'    type = "virtual";\n'
        f'  }};\n'
    )


for disk_id, purpose in [(root_disk_id, "root"), (swap_disk_id, "swap")]:
    if not has_quoted_attr_block(disks_body, disk_id):
        added_disks.append(disk_entry(disk_id, purpose))

for disk_id in ceph_disk_ids:
    if not has_quoted_attr_block(disks_body, disk_id):
        added_disks.append(disk_entry(disk_id, "ceph"))

if added_disks:
    insert_text = ("\n" if not disks_src[:root_close].endswith("\n") else "") + "".join(added_disks)
    disks_src = disks_src[:root_close] + insert_text + disks_src[root_close:]


# Patch ceph.nix
ceph_src = ceph_path.read_text()
clusters_open, clusters_close = find_block_bounds(ceph_src, "clusters = {")
hosts_open, hosts_close = find_block_bounds(ceph_src, "hosts = {")

clusters_body = ceph_src[clusters_open + 1 : clusters_close]
hosts_body = ceph_src[hosts_open + 1 : hosts_close]

cluster_entry = f'''    {cluster} = {{
      fsid = "{fsid}";
      # Set this to the {host} management IP from probe-installer output before deploy.
      monIp = "{mon_ip}";
      monHosts = [ "{fqdn}" ];
      monPort = {mon_port};
      publicNetwork = "{public_network}";
      backup = {{
        enable = false;
      }};
      bootstrap = {{
        singleHostDefaults = true;
        skipDashboard = true;
        extraArgs = [
          "--log-to-file"
          "--no-cleanup-on-failure"
        ];
      }};
      pools = [
        {{
          name = "{cluster}-images";
          application = "rbd";
          size = 1;
          minSize = 1;
        }}
        {{
          name = "{cluster}-vmdisks";
          application = "rbd";
          size = 1;
          minSize = 1;
        }}
        {{
          name = "{cluster}-k8s-ssd-1r";
          application = "rbd";
          size = 1;
          minSize = 1;
        }}
        {{
          name = "{cluster}-k8s-ssd-2r";
          application = "rbd";
          size = 1;
          minSize = 1;
        }}
        {{
          name = "{cluster}-k8s-ssd-3r";
          application = "rbd";
          size = 1;
          minSize = 1;
        }}
      ];
      cephfs = [
        {{
          name = "{cluster}-ssd-cephfs";
          metadataPool = {{
            name = "{cluster}-ssd-cephfs-meta-1r";
            size = 1;
            minSize = 1;
          }};
          dataPools = [
            {{
              name = "{cluster}-ssd-cephfs-1r";
              size = 1;
              minSize = 1;
            }}
            {{
              name = "{cluster}-ssd-cephfs-2r";
              size = 1;
              minSize = 1;
            }}
            {{
              name = "{cluster}-ssd-cephfs-3r";
              size = 1;
              minSize = 1;
            }}
          ];
          mds = {{
            count = 1;
          }};
        }}
      ];
      rgw = {{
        enable = false;
      }};
      kvmPools = [
        {{
          name = "{cluster}-ceph-images";
          pool = "{cluster}-images";
          user = "admin";
          secretUuid = "{secret_uuid}";
          keyringFile = "/etc/ceph/ceph.client.admin.keyring";
          confFile = "/etc/ceph/ceph.conf";
          monHost = "{fqdn}";
          monPort = {mon_port};
        }}
        {{
          name = "{cluster}-ceph-vmdisks";
          pool = "{cluster}-vmdisks";
          user = "admin";
          secretUuid = "{secret_uuid}";
          keyringFile = "/etc/ceph/ceph.client.admin.keyring";
          confFile = "/etc/ceph/ceph.conf";
          monHost = "{fqdn}";
          monPort = {mon_port};
        }}
      ];
    }};
'''

host_entry = f'''    {host} = {{
      cluster = "{cluster}";
      roles = [
        "bootstrap"
        "osd"
        "kvm"
      ];
    }};
'''

added_cluster = False
added_host = False

if not has_attr_block(clusters_body, cluster):
    ceph_src = ceph_src[:clusters_close] + "\n" + cluster_entry + ceph_src[clusters_close:]
    added_cluster = True

# Recompute hosts bounds if source changed
hosts_open, hosts_close = find_block_bounds(ceph_src, "hosts = {")
hosts_body = ceph_src[hosts_open + 1 : hosts_close]
if not has_attr_block(hosts_body, host):
    ceph_src = ceph_src[:hosts_close] + "\n" + host_entry + ceph_src[hosts_close:]
    added_host = True

print(f"disks_added={len(added_disks)}")
print(f"cluster_added={str(added_cluster).lower()}")
print(f"host_added={str(added_host).lower()}")

if not dry_run:
    disks_path.write_text(disks_src)
    ceph_path.write_text(ceph_src)
PY

if [[ "$dry_run" == false ]]; then
  echo ">> Updated ${disks_file} and ${ceph_file}"
else
  echo ">> Dry-run complete; no files changed"
fi

echo ">> Next:"
echo "   nix fmt"
echo "   rg -n \"${host}|${cluster}\" resources/homelab/{disks,ceph}.nix"
