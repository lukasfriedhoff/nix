# Nix Repo Agent Notes

- Run `nix fmt` (nixfmt) before committing any `.nix` changes.
- Prefer `./scripts/checks.sh` to validate formatting + `nix flake check`.
- If the git hook reformats files, re-stage the changes and re-run the commit.
