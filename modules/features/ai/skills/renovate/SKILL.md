---
name: renovate
description: Find and review Renovate dependency PRs in the homelab GitOps repos. Use when asked to check/list/merge Renovate PRs or dependency updates.
---

# Renovate (homelab GitOps)

Renovate keeps dependency versions current in the FluxCD repos. Checking its PRs
has two traps that make it silently look like "no PRs" — read both before running.

## How it runs here
- **GitHub Actions**, not the hosted Renovate app: `flux-apps/.github/workflows/renovate.yml`,
  cron `23 5 * * *` (daily 05:23 UTC).
- **Scope is only two repos** — `RENOVATE_REPOSITORIES: "lukasfriedhoff/flux-apps,lukasfriedhoff/flux-cluster"`.
  nix, flux-app-media, logDay, etc. are NOT managed by Renovate (don't expect PRs there).
- Config: `flux-apps/renovate.json` and `flux-cluster/renovate.json`.
- `flux-apps-monitoring` is **not** a GitHub repo under that name (gh returns a 404) — local/other remote only.

## Trap 1 — `gh` is not in PATH; NEVER swallow stderr
`gh` isn't installed in the default shell. Invoke it via nixpkgs:
```sh
nix run nixpkgs#gh -- pr list --repo lukasfriedhoff/flux-apps --state open
```
And do **not** pipe tool calls through `2>/dev/null` — a `command not found` then
looks identical to "0 results" and you'll misreport "no PRs." Check stderr / exit codes.
(See the `feedback-nixpkgs-for-missing-tools` memory.)

## Trap 2 — Renovate commits as the USER, not `renovate[bot]`
It runs with a PAT (`RENOVATE_TOKEN`), so PRs are **authored by `lukasfriedhoff`**, not
`renovate[bot]`/`app/renovate`. Filtering `--author app/renovate` returns nothing.
Filter by the **`renovate` label** (applied to every Renovate PR) or the `chore(deps):` title:
```sh
nix run nixpkgs#gh -- pr list --repo lukasfriedhoff/flux-apps --label renovate --state open \
  --json number,title,createdAt --jq '.[] | "#\(.number) \(.title)"'
```

## Checking both managed repos
```sh
for r in flux-apps flux-cluster; do
  echo "== $r =="
  nix run nixpkgs#gh -- pr list --repo lukasfriedhoff/$r --label renovate --state open \
    --json number,title --jq '.[] | "#\(.number) \(.title)"'
done
```

## Review / merge a PR
```sh
nix run nixpkgs#gh -- pr view  <N> --repo lukasfriedhoff/flux-apps           # body, files, checks
nix run nixpkgs#gh -- pr checks <N> --repo lukasfriedhoff/flux-apps          # CI (flux build/validate)
nix run nixpkgs#gh -- pr diff  <N> --repo lukasfriedhoff/flux-apps
nix run nixpkgs#gh -- pr merge <N> --repo lukasfriedhoff/flux-apps --squash  # only after CI green
```
For **major** bumps (e.g. groupfolders v22→v23, richdocuments→v12) check the app's
Nextcloud/Helm compatibility before merging — Renovate bumps the pin, not the compat.
The Nextcloud app pins are URL+sha256+version triples (see the
`nextcloud-custom-apps-renovate` memory): a major that needs a newer Nextcloud can break the seed.

## Dependency Dashboard
Renovate opens a "Dependency Dashboard" **issue** in each managed repo listing pending,
rate-limited, and errored updates (not everything becomes a PR immediately):
```sh
nix run nixpkgs#gh -- issue list --repo lukasfriedhoff/flux-apps --search "Dependency Dashboard in:title"
```
