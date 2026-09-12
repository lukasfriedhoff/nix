---
name: durs
description: durs — fast Rust disk-usage analyzer (du replacement); use for "what's eating disk space" questions on hosts, PVCs, and containers
---

# durs — Disk Usage Analyzer

Fast `du` replacement in Rust with color-coded output, automatic depth selection, and graceful permission-error handling. Upstream: https://github.com/trinhminhtriet/durs (also mirrored at rust-rs/durs).

## Install

**Not in nixpkgs.** Options, in preference order:

```bash
# 1. cargo install (puts binary in ~/.cargo/bin)
nix shell nixpkgs#cargo nixpkgs#rustc -c cargo install durs

# 2. Packaged fallback with near-identical purpose (IS in nixpkgs):
nix run nixpkgs#dust -- <dir>
```

If durs isn't installed and the question is one-shot, prefer the `dust` fallback over compiling. Never hardcode /nix/store paths.

## Usage

```bash
durs <dir>            # analyze a directory (auto depth, sorted, colored)
durs -n 30 <dir>      # show 30 entries (default: terminal height)
durs -d 3 <dir>       # limit to 3 levels of subdirectories
durs -D <dir>         # directories only
durs -F <dir>         # files only
durs -p <dir>         # print full paths
durs -s <dir>         # apparent size (like du --apparent-size)
durs -z 10M <dir>     # hide entries smaller than 10M
durs -e '\.log$'      # only entries matching regex
durs -v node_modules  # exclude entries matching regex
durs -j <dir>         # JSON output (for scripting/parsing)
durs -x <dir>         # stay on one filesystem (skip mounts) — important on hosts with NFS/Longhorn mounts
durs -L <dir>         # follow symlinks
durs -c               # monochrome (for logs/pipes)
```

Config file: `~/.config/durs/config.toml` for persistent defaults.

## Homelab patterns

- **Host disk pressure**: `durs -x -n 25 /` (the `-x` avoids descending into NFS/Longhorn/ceph mounts and inflating results).
- **Inside a pod/PVC**: containers won't have durs; use plain `du` there, or `-j` from a debug image:
  `kubectl -n <ns> exec <pod> -- du -x -h -d2 /data | sort -rh | head -20`
- **storage01 (docker host, non-root SSH)**: run in a container with the mount bound:
  `ssh storage01 docker run --rm -v /mnt/backup:/scan:ro alpine sh -c 'du -x -h -d2 /scan | sort -rh | head -20'`
  (NEVER run anything that writes/deletes on MinIO data paths — inspect read-only.)
- **Scripting**: prefer `durs -j` and parse JSON instead of scraping the colored table.
