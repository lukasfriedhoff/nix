# Hydra + Attic Binary Cache

This repo exposes `hydraJobs.nixosConfigurations`, so Hydra can build every
NixOS host configuration in the flake. Use Attic as the binary cache behind it:
Hydra schedules and builds, Attic stores and serves substitutes.

## Recommended topology

- `srv3`: Hydra evaluator/builder and Attic cache server.
- Clients: use the Attic cache as a high-priority substituter before
  `cache.nixos.org`.
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

Store it in a root-only environment file on the Attic host:

```ini
ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="..."
```

`srv3` enables `services.atticd` via `lukasf.atticCache` and currently exposes
it on the lab URL:

```text
http://attic.lab.h4xx.io:8080
```

It uses local SQLite/storage for the first homelab iteration. Put it behind
HTTPS before exposing it outside the lab.

After `atticd` starts, create a cache and token:

```bash
sudo atticd-atticadm make-token \
  --sub hydra \
  --validity 10y \
  --pull homelab \
  --push homelab \
  --create-cache homelab \
  --configure-cache homelab

attic login srv3 http://attic.lab.h4xx.io:8080 <TOKEN>
attic cache create srv3:homelab --public --priority 30
attic cache info srv3:homelab
```

Then write the public key from `attic cache info` to:

```text
resources/attic-cache/homelab.pub
```

Clients migrate automatically once that file exists. Until then, they keep using
the legacy `nix-serve` cache.

```nix
nix.settings = {
  substituters = [
    "http://attic.lab.h4xx.io:8080/homelab?priority=30"
    "https://cache.nixos.org"
  ];
  trusted-public-keys = [
    "homelab:..."
  ];
};
```

## Populating Attic

Hydra does not push to Attic automatically unless configured to do so. The
minimal bridge is a post-build/upload job that pushes completed result paths:

```bash
attic push srv3:homelab ./result
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
