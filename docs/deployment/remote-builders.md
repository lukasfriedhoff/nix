# Remote Builders (srv3) GitOps Runbook

This runbook documents how remote builds are wired for personal desktops and how to safely cap resources on the builder host (`srv3`) without breaking binary cache behavior.

## Current design

- Builder host: `srv3.lab.h4xx.io`
- SSH build user: `nixbuilder` (dedicated system user)
- Client-side builder scheduling cap: `maxJobs = 2`
- Builder-side execution caps:
  - `nix.settings.max-jobs = 5`
  - `nix.settings.cores = 4`
- Cgroup resource caps:
  - remote SSH build sessions stay in `user-31000.slice`
  - local Hydra builds run through `nix-daemon.service` in `hydra-builds.slice`
  - `CPUQuota = "2200%"`
  - `MemoryHigh = "60G"`
  - `MemoryMax = "64G"`
- `srv3` keeps Hydra local and queues/uploads build outputs to Kubernetes Attic
  at `https://attic-testing.h4xx.io`.
- Client defaults must stay on the old cache URL until the new Kubernetes Attic
  cache public key is committed to `resources/attic-cache/homelab.pub`.

## Why dedicated user

Root-based remote builds run in `user-0.slice`, which would throttle all root SSH sessions if capped.
Using `nixbuilder` isolates only remote build traffic into `user-31000.slice`.
Hydra itself already runs as dedicated `hydra` and `hydra-queue-runner` users, but the actual builds are spawned by `nix-daemon` as `nixbld*` users. For that reason, local Hydra build pressure is capped by moving `nix-daemon.service` into `hydra-builds.slice`.

## Files involved

- Client defaults: `hosts/common/default.nix`
- Builder host config: `hosts/homelab/srv3/configuration.nix`

## Rollout via GitOps

1. Commit and push changes to `develop` in this repo.
2. On `srv3`, pull/apply with comin:

```bash
ssh srv3 'comin fetch'
ssh srv3 'journalctl -u comin.service -n 120 --no-pager -l'
```

3. Verify host-side state:

```bash
ssh srv3 'id nixbuilder'
ssh srv3 'nix show-config | grep -E "^(max-jobs|cores|builders)"'
ssh srv3 'systemctl show user-31000.slice -p CPUQuotaPerSecUSec -p MemoryHigh -p MemoryMax'
ssh srv3 'systemctl show hydra-builds.slice nix-daemon.service -p Slice -p CPUQuotaPerSecUSec -p MemoryHigh -p MemoryMax'
```

4. Verify client-side effective config (example: tux):

```bash
nix eval --json .#nixosConfigurations.tux-h4xx-01.config.lukasf.remoteBuilds.sshUser
nix eval --json .#nixosConfigurations.tux-h4xx-01.config.lukasf.remoteBuilds.maxJobs
```

5. Functional smoke test from a personal desktop:

```bash
ssh nixbuilder@srv3.lab.h4xx.io 'id'
# then trigger a normal nix build on the desktop and observe it schedules remote jobs
```

## Cache and artifact safety

- Existing `/nix/store` content is unchanged.
- Existing `/nix/var/nix` database is unchanged.
- `nix-serve` keeps serving existing and new artifacts.
- Kubernetes Attic starts with a fresh cache signing key unless its database is
  migrated; update `resources/attic-cache/homelab.pub` before moving clients to
  `https://attic-testing.h4xx.io`.
- Attic uploads are queued by the Nix post-build hook and drained by
  `attic-post-build-drain.timer`; the hook no longer blocks Hydra build slots.
- No cache key rotation is needed if the Kubernetes Attic deployment reuses the
  existing server token secret.

## Troubleshooting

- If `ssh nixbuilder@srv3.lab.h4xx.io` fails:
  - verify authorized key source in `hosts/homelab/srv3/initrd-authorized.pub`
  - verify client key path from `sops.secrets."srv3-builder-key"`
- If remote builds do not schedule:
  - check `nix build --verbose` output on client
  - check `ssh srv3 'journalctl -u nix-daemon -n 200 --no-pager'`
- If cgroup limits not applied:
  - `ssh srv3 'systemctl status user-31000.slice --no-pager -l'`
- If Attic uploads lag:
  - `ssh srv3 'systemctl status attic-post-build-drain.timer attic-post-build-drain.service --no-pager -l'`
  - `ssh srv3 'find /var/lib/attic-upload/queue -type f | wc -l'`
  - `ssh srv3 'tail -n 200 /var/log/attic-post-build-upload.log'`
