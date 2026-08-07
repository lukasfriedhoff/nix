# ISO Artifacts

This directory stores installer ISOs used by local/remote VM bootstrap workflows.

## Current artifact

- `nixos-minimal-ci-ssh.iso` — **not tracked in git**

ISOs are gitignored. This repository is public, and at ~1.3 GB the artifact
exceeded GitHub's free Git-LFS quota (1 GiB storage, 1 GiB/month bandwidth),
where every clone would have billed against that allowance. Supply the file
locally instead: place it in this directory, or point the scripts at it with

```bash
export TESTINGRKE2_INSTALLER_ISO=/path/to/nixos-minimal-ci-ssh.iso
```

## Intended use

Use this ISO with `scripts/vms/new-qemu-vm.sh --mode iso` when bootstrapping VMs
that will be deployed with `scripts/servers/deploy-from-iso.sh`.

Example:

```bash
scripts/vms/new-qemu-vm.sh \
  --name srv3 \
  --mode iso \
  --iso artifacts/iso/nixos-minimal-ci-ssh.iso \
  --memory 16384 \
  --vcpus 8 \
  --disk-size 100 \
  --disk-serial srv3-root
```

## Validation

Before using the artifact, verify checksum and metadata:

```bash
sha256sum artifacts/iso/nixos-minimal-ci-ssh.iso
file artifacts/iso/nixos-minimal-ci-ssh.iso
```

## Lifecycle / maintenance

- Keep only actively used ISO artifacts in this folder.
- If replacing `nixos-minimal-ci-ssh.iso`, record:
  - source (URL or build method),
  - checksum,
  - date and operator,
  - affected runbooks.
- Update related docs when the artifact name or workflow changes:
  - `docs/deployment/qemu-vm-bootstrap.md`
  - `docs/deployment/remote-servers.md`

## Related runbooks

- `docs/deployment/qemu-vm-bootstrap.md`
- `docs/deployment/remote-servers.md`
- `docs/deployment/personal-homelab.md`
