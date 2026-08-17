# Manual Todo Checklist

Live manual follow-ups for the Nix repo. Historical one-time checklists (Codex
integration, K9s hotkeys, in-repo secrets verification) have been removed;
secrets now live in the private nix-secrets repo (see
`docs/architecture/secrets-routing.md`).

## 1. Password rotation after the nix-secrets split

- **Rotate the shared personal login password** — the old hash is public in
  this repo's git history. Generate a new hash with `mkpasswd -m sha-512`, then
  on a personal desktop edit the secret in the nix-secrets checkout:
  ```bash
  sops ../nix-secrets/secrets/profiles/personal/shared/login-password-hash.txt
  ```
  `users.users.*.hashedPasswordFile` is declarative, so editing the secret and
  redeploying the affected hosts is enough — no manual `passwd` runs needed.
  (`srv9` keeps its own per-host `login-password-hash.txt`.)
- **Work servers** (`dacoso.server`) now read
  `<server>/root-password-hash.txt` and `nixos-password-hash.txt` via sops-nix
  and require an age key at `/var/lib/sops-nix/age/keys.txt` — put it in place
  on each work server **before** the next deploy. Defaults also changed:
  `PermitRootLogin prohibit-password`, SSH password authentication off,
  firewall on.

## 2. Repo-Wide Follow-ups (Dec 2025)

- Run `sudo nixos-rebuild switch --flake /home/lukasf/git/lukasfriedhoff/nix#tux-h4xx-01` once the stylix/Home Manager warning is addressed and keep an eye on `/mnt/windows` (currently fails because `nvme1n1p2` is dirty NTFS; either repair in Windows or run `ntfsfix` before the next switch).
- Validate the new Icarus Mod Manager launcher (`modules/features/gaming/icarus-mod-manager/home.nix`) on tux: ensure the Wine prefix gets `.NET 8` installed and document any manual mod import/export workflow.
- Decide whether stylix should manage fontconfig again. If yes, drop `fonts.fontconfig.enable = lib.mkForce false;` (`modules/features/platform/linux/home.nix`) and reconfigure stylix’ font targets so `home-manager.users.*.fonts.fontconfig` stops evaluating to `null`.
- Review SSH layout simplification opportunities: `resources/ssh/hosts/personal.nix` duplicates some `identityFile` paths that now live under `~/.ssh/personal`. Consider deriving them automatically from `identity` enums to keep host entries smaller.
