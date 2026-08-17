#!/usr/bin/env bash

set -euo pipefail

# Prefer Nix-provided Bash on macOS (default /bin/bash is 3.2; empty-array
# expansion under `set -u` errors there).
if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
  for candidate in \
    /run/current-system/sw/bin/bash \
    "/etc/profiles/per-user/${USER:-}/bin/bash"; do
    if [[ -x "$candidate" ]]; then
      exec "$candidate" "$0" "$@"
    fi
  done
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

. "${repo_root}/scripts/lib/common.sh"

readonly network_name="testingrke2"
readonly network_gateway="192.168.124.1"
readonly api_vip="192.168.124.10"
readonly image_dir="${TESTINGRKE2_IMAGE_DIR:-/data/libvirt/images/testingrke2}"
readonly installer_iso="${TESTINGRKE2_INSTALLER_ISO:-${repo_root}/artifacts/iso/nixos-minimal-ci-ssh.iso}"
readonly kubeconfig_path="${TESTINGRKE2_KUBECONFIG:-${HOME}/.kube/testingrke2.yaml}"

readonly -a nodes=(
  "testingrke2-01"
  "testingrke2-02"
  "testingrke2-03"
)
readonly -a node_ips=(
  "192.168.124.11"
  "192.168.124.12"
  "192.168.124.13"
)
readonly -a node_macs=(
  "52:54:00:72:6b:11"
  "52:54:00:72:6b:12"
  "52:54:00:72:6b:13"
)

usage() {
  cat <<'EOF'
Usage: scripts/vms/testingrke2-lab.sh <command> [options]

Commands:
  network                 Define and start the isolated testingrke2 NAT network
  create                  Create and start all three RKE2 VMs
  authorize [node|all]    Install each node management key in the live installer
  deploy <node|all>       Install NixOS, unlock, and wait for each selected node
  bootstrap               Run network, create, authorize, deploy, and kubeconfig
  kubeconfig              Fetch the RKE2 kubeconfig from testingrke2-01
  status                  Show network, VM, RKE2, and Flux status
  start                   Start all existing VMs
  stop                    Gracefully stop all existing VMs
  destroy --confirm       Delete the VMs, their disks, and the libvirt network

Environment:
  TESTINGRKE2_IMAGE_DIR          VM image directory
  TESTINGRKE2_INSTALLER_ISO      Installer ISO
  TESTINGRKE2_INSTALLER_IDENTITY Existing key baked into the installer ISO
  TESTINGRKE2_KUBECONFIG         Destination kubeconfig
  TESTINGRKE2_DRY_RUN=1          Print mutating commands without running them
EOF
}

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  if [[ "${TESTINGRKE2_DRY_RUN:-0}" != "1" ]]; then
    "$@"
  fi
}

node_index() {
  local requested="$1"
  local index
  for index in "${!nodes[@]}"; do
    if [[ "${nodes[$index]}" == "$requested" ]]; then
      printf '%s\n' "$index"
      return 0
    fi
  done
  die "unknown node: ${requested}"
}

selected_nodes() {
  local requested="${1:-all}"
  if [[ "$requested" == "all" ]]; then
    printf '%s\n' "${nodes[@]}"
  else
    node_index "$requested" >/dev/null
    printf '%s\n' "$requested"
  fi
}

network_xml() {
  cat <<EOF
<network>
  <name>${network_name}</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr-rke2' stp='on' delay='0'/>
  <domain name='testingrke2.lab.h4xx.io' localOnly='yes'/>
  <ip address='${network_gateway}' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.124.100' end='192.168.124.199'/>
      <host mac='${node_macs[0]}' name='${nodes[0]}' ip='${node_ips[0]}'/>
      <host mac='${node_macs[1]}' name='${nodes[1]}' ip='${node_ips[1]}'/>
      <host mac='${node_macs[2]}' name='${nodes[2]}' ip='${node_ips[2]}'/>
    </dhcp>
  </ip>
</network>
EOF
}

ensure_network() (
  local xml
  xml="$(mktemp)"
  trap 'rm -f "$xml"' EXIT
  network_xml >"$xml"

  if ! virsh --connect qemu:///system net-info "$network_name" >/dev/null 2>&1; then
    run virsh --connect qemu:///system net-define "$xml"
  fi
  run virsh --connect qemu:///system net-autostart "$network_name"
  if ! virsh --connect qemu:///system net-info "$network_name" 2>/dev/null | grep -q 'Active:.*yes'; then
    run virsh --connect qemu:///system net-start "$network_name"
  fi
)

ensure_image_dir() {
  if [[ -d "$image_dir" && -w "$image_dir" ]]; then
    return
  fi
  if [[ -w "$(dirname "$image_dir")" ]]; then
    run install -d -m 0755 "$image_dir"
  else
    run sudo install -d -m 0755 -o "$USER" -g users "$image_dir"
  fi
}

create_vms() {
  [[ -f "$installer_iso" ]] || die "installer ISO not found: ${installer_iso}"
  ensure_network
  ensure_image_dir

  local index node
  for index in "${!nodes[@]}"; do
    node="${nodes[$index]}"
    if virsh --connect qemu:///system dominfo "$node" >/dev/null 2>&1; then
      log "${node} already exists; leaving it unchanged"
      continue
    fi
    run "$repo_root/scripts/vms/new-qemu-vm.sh" \
      --name "$node" \
      --mode iso \
      --iso "$installer_iso" \
      --libosinfo-os-id http://nixos.org/nixos/unstable \
      --memory 8192 \
      --vcpus 4 \
      --disk-size 80 \
      --disk-path "${image_dir}/${node}-root.qcow2" \
      --disk-serial "trke2-$((index + 1))-root" \
      --extra-disk "500:trke2-$((index + 1))-lh1" \
      --network "$network_name" \
      --mac-address "${node_macs[$index]}" \
      --graphics vnc \
      --autostart
  done
}

decrypt_node_key() {
  local node="$1"
  local destination="$2"
  local secrets_dir source
  secrets_dir="$(secrets_root)"
  source="${secrets_dir}/secrets/profiles/personal/desktops/common/ssh/${node}-personal-mgmt.priv"
  [[ -f "$source" ]] || die "encrypted management key not found: ${source}"
  SOPS_CONFIG="${secrets_dir}/.sops.yaml" sops -d "$source" >"$destination"
  chmod 0600 "$destination"
}

installer_identity() {
  local candidate
  if [[ -n "${TESTINGRKE2_INSTALLER_IDENTITY:-}" ]]; then
    [[ -f "$TESTINGRKE2_INSTALLER_IDENTITY" ]] || die "installer identity not found"
    printf '%s\n' "$TESTINGRKE2_INSTALLER_IDENTITY"
    return
  fi
  for candidate in \
    "$HOME/.ssh/personal/ci" \
    "$HOME/.ssh/personal/srv3-personal-mgmt" \
    "$HOME/.ssh/personal/id_ed25519"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  die "set TESTINGRKE2_INSTALLER_IDENTITY to a key baked into the installer ISO"
}

wait_for_ssh() {
  local ip="$1"
  local port="$2"
  local key="$3"
  local attempts="${4:-120}"
  local attempt
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if ssh \
      -i "$key" \
      -p "$port" \
      -o BatchMode=yes \
      -o ConnectTimeout=2 \
      -o IdentitiesOnly=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "root@${ip}" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

authorize_installers() {
  local requested="${1:-all}"
  local bootstrap_key
  bootstrap_key="$(installer_identity)"
  local node index ip public_key
  while IFS= read -r node; do
    index="$(node_index "$node")"
    ip="${node_ips[$index]}"
    public_key="hosts/homelab/${node}/initrd-authorized.pub"
    [[ -f "$public_key" ]] || die "public key not found: ${public_key}"
    log "authorizing ${node} on installer ${ip}"
    wait_for_ssh "$ip" 22 "$bootstrap_key" 60 \
      || die "installer SSH did not become ready for ${node} at ${ip}"
    run ssh \
      -i "$bootstrap_key" \
      -o IdentitiesOnly=yes \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      "root@${ip}" \
      "umask 077; mkdir -p /root/.ssh; cat >>/root/.ssh/authorized_keys" \
      <"$public_key"
  done < <(selected_nodes "$requested")
}

wait_for_api() {
  local attempts="${1:-180}"
  local attempt
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl --fail --insecure --silent --max-time 2 "https://${api_vip}:6443/readyz" >/dev/null; then
      return 0
    fi
    sleep 2
  done
  return 1
}

deploy_one() (
  local node="$1"
  local index ip key secrets_dir
  index="$(node_index "$node")"
  ip="${node_ips[$index]}"
  secrets_dir="$(secrets_root)"
  key="$(mktemp)"
  trap 'rm -f "$key"' EXIT
  decrypt_node_key "$node" "$key"

  log "deploying ${node} to ${ip}"
  run "$repo_root/scripts/servers/deploy-from-iso.sh" \
    "$node" \
    "root@${ip}" \
    --identity "$key" \
    --ssh-option IdentitiesOnly=yes \
    --luks-secret "${secrets_dir}/secrets/profiles/personal/shared/luks/${node}.txt"

  if [[ "${TESTINGRKE2_DRY_RUN:-0}" == "1" ]]; then
    return
  fi

  log "waiting for ${node} initrd SSH"
  wait_for_ssh "$ip" 2222 "$key" 180 \
    || die "initrd SSH did not become ready for ${node}"
  "$repo_root/scripts/homelab/unlock.sh" \
    "$node" \
    --target "root@${ip}" \
    --port 2222 \
    --identity "$key"
  log "waiting for ${node} stage 2 SSH"
  wait_for_ssh "$ip" 22 "$key" 240 \
    || die "installed SSH did not become ready for ${node}"
)

deploy_nodes() {
  local requested="${1:-all}"
  local node
  while IFS= read -r node; do
    deploy_one "$node"
    if [[ "$node" == "${nodes[0]}" && "${TESTINGRKE2_DRY_RUN:-0}" != "1" ]]; then
      log "waiting for the RKE2 API virtual IP"
      wait_for_api || die "RKE2 API did not become ready at ${api_vip}"
    fi
  done < <(selected_nodes "$requested")
}

fetch_kubeconfig() (
  local key
  key="$(mktemp)"
  trap 'rm -f "$key"' EXIT
  decrypt_node_key "${nodes[0]}" "$key"
  run install -d -m 0700 "$(dirname "$kubeconfig_path")"
  if [[ "${TESTINGRKE2_DRY_RUN:-0}" == "1" ]]; then
    log "would fetch kubeconfig to ${kubeconfig_path}"
    return
  fi
  ssh \
    -i "$key" \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "root@${node_ips[0]}" \
    "cat /etc/rancher/rke2/rke2.yaml" \
    | sed "s#https://127.0.0.1:6443#https://${api_vip}:6443#" \
    >"$kubeconfig_path"
  chmod 0600 "$kubeconfig_path"
  log "wrote ${kubeconfig_path}"
)

show_status() {
  virsh --connect qemu:///system net-info "$network_name" || true
  printf '\n'
  virsh --connect qemu:///system list --all | {
    read -r header || true
    printf '%s\n' "$header"
    grep -E 'testingrke2|^ *$' || true
  }
  if [[ -f "$kubeconfig_path" ]]; then
    printf '\n'
    KUBECONFIG="$kubeconfig_path" kubectl get nodes -o wide || true
    printf '\n'
    KUBECONFIG="$kubeconfig_path" flux get all -A || true
  fi
}

start_vms() {
  local node
  for node in "${nodes[@]}"; do
    if virsh --connect qemu:///system dominfo "$node" >/dev/null 2>&1 \
      && ! virsh --connect qemu:///system domstate "$node" | grep -q running; then
      run virsh --connect qemu:///system start "$node"
    fi
  done
}

stop_vms() {
  local node
  for node in "${nodes[@]}"; do
    if virsh --connect qemu:///system dominfo "$node" >/dev/null 2>&1 \
      && virsh --connect qemu:///system domstate "$node" | grep -q running; then
      run virsh --connect qemu:///system shutdown "$node"
    fi
  done
}

destroy_lab() {
  [[ "${1:-}" == "--confirm" ]] || die "destroy requires --confirm"
  local node
  for node in "${nodes[@]}"; do
    if virsh --connect qemu:///system dominfo "$node" >/dev/null 2>&1; then
      run virsh --connect qemu:///system destroy "$node" || true
      run virsh --connect qemu:///system undefine "$node" --nvram --remove-all-storage
    fi
  done
  if virsh --connect qemu:///system net-info "$network_name" >/dev/null 2>&1; then
    run virsh --connect qemu:///system net-destroy "$network_name" || true
    run virsh --connect qemu:///system net-undefine "$network_name"
  fi
}

command="${1:-}"
shift || true

case "$command" in
  network)
    ensure_network
    ;;
  create)
    create_vms
    ;;
  authorize)
    authorize_installers "${1:-all}"
    ;;
  deploy)
    deploy_nodes "${1:-all}"
    ;;
  bootstrap)
    ensure_network
    create_vms
    authorize_installers all
    deploy_nodes all
    fetch_kubeconfig
    show_status
    ;;
  kubeconfig)
    fetch_kubeconfig
    ;;
  status)
    show_status
    ;;
  start)
    start_vms
    ;;
  stop)
    stop_vms
    ;;
  destroy)
    destroy_lab "${1:-}"
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
