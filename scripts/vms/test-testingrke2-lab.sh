#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

. "${repo_root}/scripts/lib/common.sh"

secrets_dir="$(secrets_root)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "$file" || fail "${file} does not contain: ${text}"
}

bash -n scripts/vms/new-qemu-vm.sh
bash -n scripts/vms/testingrke2-lab.sh
scripts/vms/testingrke2-lab.sh help >/dev/null

dry_run_output="$(mktemp)"
trap 'rm -f "$dry_run_output"' EXIT
TESTINGRKE2_DRY_RUN=1 \
  TESTINGRKE2_IMAGE_DIR=/tmp/testingrke2-test-images \
  scripts/vms/testingrke2-lab.sh create >"$dry_run_output" 2>&1

assert_contains scripts/vms/new-qemu-vm.sh '--mac-address'
assert_contains scripts/vms/testingrke2-lab.sh 'readonly api_vip="192.168.124.10"'
assert_contains scripts/vms/testingrke2-lab.sh '"192.168.124.11"'
assert_contains scripts/vms/testingrke2-lab.sh '"192.168.124.12"'
assert_contains scripts/vms/testingrke2-lab.sh '"192.168.124.13"'
assert_contains scripts/vms/testingrke2-lab.sh '"52:54:00:72:6b:11"'
assert_contains scripts/vms/testingrke2-lab.sh '"52:54:00:72:6b:12"'
assert_contains scripts/vms/testingrke2-lab.sh '"52:54:00:72:6b:13"'

for index in 01 02 03; do
  host="testingrke2-${index}"
  assert_contains "$dry_run_output" "--name ${host}"
  test -f "hosts/homelab/${host}/configuration.nix" \
    || fail "missing host configuration for ${host}"
  test -f "hosts/homelab/${host}/initrd-authorized.pub" \
    || fail "missing initrd key for ${host}"
  test -f "${secrets_dir}/secrets/profiles/personal/servers/${host}/rke2-token.txt" \
    || fail "missing encrypted RKE2 token for ${host}"
  test -f "${secrets_dir}/secrets/profiles/personal/shared/luks/${host}.txt" \
    || fail "missing encrypted LUKS secret for ${host}"
  assert_contains flake.nix "${host} ="
  assert_contains "${secrets_dir}/.sops.yaml" "# ${host}"
done

token_hashes="$(
  for index in 01 02 03; do
    sha256sum "${secrets_dir}/secrets/profiles/personal/servers/testingrke2-${index}/rke2-token.txt"
  done | cut -d' ' -f1 | sort -u | wc -l
)"
if [[ "$token_hashes" -ne 3 ]]; then
  fail "encrypted token files should use independent SOPS envelopes"
fi

assert_contains hosts/homelab/testingrke2/node.nix 'distribution = "rke2";'
assert_contains hosts/homelab/testingrke2/node.nix 'path = "./overlays/testingrke2";'
assert_contains hosts/homelab/testingrke2/node.nix 'virtualRouterId = 72;'
assert_contains hosts/homelab/testingrke2/disko.nix '/var/lib/longhorn-disk1'

printf 'testingrke2 VM topology checks passed.\n'
