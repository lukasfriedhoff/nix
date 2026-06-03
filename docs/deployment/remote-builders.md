# Remote Builders (srv3) GitOps Runbook

This runbook documents how remote builds are wired for personal desktops and how to safely cap resources on the builder host (`srv3`) without breaking binary cache behavior.

## Current design

- Builder host: `srv3.lab.h4xx.io`
- SSH build user: `nixbuilder` (dedicated system user)
- Client-side builder scheduling cap: `maxJobs = 2`
- Builder-side execution caps:
  - `nix.settings.max-jobs = 2`
  - `nix.settings.cores = 11`
- Cgroup resource caps:
  - remote SSH build sessions stay in `user-31000.slice`
  - local Hydra builds run through `nix-daemon.service` in `hydra-builds.slice`
  - `CPUQuota = "2200%"`
  - `MemoryHigh = "60G"`
  - `MemoryMax = "64G"`
- Cache remains enabled (`nix-serve` on `srv3`), no artifact migration required.

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
- No cache key rotation needed for this change.

## Troubleshooting

- If `ssh nixbuilder@srv3.lab.h4xx.io` fails:
  - verify authorized key source in `hosts/homelab/srv3/initrd-authorized.pub`
  - verify client key path from `sops.secrets."srv3-builder-key"`
- If remote builds do not schedule:
  - check `nix build --verbose` output on client
  - check `ssh srv3 'journalctl -u nix-daemon -n 200 --no-pager'`
- If cgroup limits not applied:
  - `ssh srv3 'systemctl status user-31000.slice --no-pager -l'`
