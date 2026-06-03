# Hydra + Attic Binary Cache

This repo exposes `hydraJobs.nixosConfigurations`, so Hydra can build every
NixOS host configuration in the flake. Use Attic as the binary cache behind it:
Hydra schedules and builds, Attic stores and serves substitutes.

## Current topology

- `srv3`: Hydra evaluator/builder and upload queue/drainer.
- Kubernetes testing cluster: Attic server at `https://attic-testing.h4xx.io`,
  backed by CNPG Postgres and a persistent storage PVC.
- Clients: use the committed Attic URL/public key pair as a high-priority
  substituter before `cache.nixos.org`.
- Jobset: a flake jobset pointing at this repo's `develop` branch.

This avoids doing builds during `nixos-rebuild switch` on laptops and servers:
Hydra prebuilds `.#hydraJobs.nixosConfigurations.*`, then clients substitute the
already-built closures from Attic.

## Hydra jobset

Create a Hydra project/jobset with:

- Type: `Flake`
- Flake URI: `git+https://github.com/lukasfriedhoff/nix.git?ref=develop`
- Output: `hydraJobs`

The relevant output can be inspected locally:

```bash
nix eval --json .#hydraJobs.nixosConfigurations --apply builtins.attrNames
nix build .#hydraJobs.nixosConfigurations.srv2
```

## Attic bootstrap

Attic requires one server JWT secret:

```bash
nix run nixpkgs#openssl -- genrsa -traditional 4096 | base64 -w0
```

Store it as the shared server token secret:

```ini
ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="..."
```

The Kubernetes deployment consumes the same key via the `attic-server-env`
Secret in the `nix-cache` namespace. `srv3` also decrypts the same secret only
to mint the local upload token for Hydra.

The testing deployment exposes Attic at:

```text
https://attic-testing.h4xx.io
```

The Flux bootstrap job creates the `homelab` cache as public with priority 30.
A fresh Kubernetes Attic database creates a fresh cache signing key. Do not move
clients to `https://attic-testing.h4xx.io` until the new public key from
`attic cache info` is committed to `resources/attic-cache/homelab.pub`.

For manual bootstrap or repair, create a token with:

```bash
atticadm -f /path/to/attic-server.toml make-token \
  --sub hydra \
  --validity 10y \
  --pull homelab \
  --push homelab \
  --create-cache homelab \
  --configure-cache homelab

attic login srv3 https://attic-testing.h4xx.io <TOKEN>
attic cache create srv3:homelab --public --priority 30
attic cache info srv3:homelab
```

Then write the public key from `attic cache info` to:

```text
resources/attic-cache/homelab.pub
```

Clients migrate automatically after both the URL and public key in this repo
match the running Attic cache. Until then, keep client defaults on the previous
cache URL to avoid signature mismatches.

```nix
nix.settings = {
  substituters = [
    "https://attic-testing.h4xx.io/homelab?priority=30"
    "https://cache.nixos.org"
  ];
  trusted-public-keys = [
    "homelab:..."
  ];
};
```

## Populating Attic

`srv3` enables `lukasf.atticCache.postBuildUpload`, which prepares a local
Attic upload token and configures the Nix daemon `post-build-hook`. The hook
only queues completed output paths under `/var/lib/attic-upload/queue`, then
`attic-post-build-drain.timer` uploads queued paths to `srv3:homelab`.

Hydra builds stay on `srv3`; only Attic serving/storage moved into Kubernetes.

Check the upload bridge with:

```bash
systemctl status attic-post-build-login.service
systemctl status attic-post-build-drain.timer attic-post-build-drain.service
find /var/lib/attic-upload/queue -type f | wc -l
tail -f /var/log/attic-post-build-upload.log
```

For manual prewarming without Hydra:

```bash
nix build \
  .#hydraJobs.nixosConfigurations.srv1 \
  .#hydraJobs.nixosConfigurations.srv2 \
  .#hydraJobs.nixosConfigurations.srv3

attic push srv3:homelab ./result*
```

## Decision

Start with `Hydra + Attic` for this repo. Attic alone is only a cache; it does
not decide what should be built. Hydra alone can build but does not give clients
a modern deduplicating cache unless paired with a cache service.
