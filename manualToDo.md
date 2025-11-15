# Manual Todo Checklist

Companion to the Codex automation for the Nix repo.

## 1. Flux-Friendly K9s Configuration
- Launch `k9s` and open the Kustomizations view (`Shift + F`).
- Pick a real workload kustomization and press:
  - `Shift + R` to reconcile (confirm Flux CLI runs the operation).
  - `Shift + S` then `Shift + U` to suspend/resume.
- Switch to the HelmRelease view (`Shift + L`) and repeat the shortcuts (`Shift + H/J/K`).
- Confirm `flux` CLI is functional from your shell (`flux -v`).

## 2. Secrets Layout Verification
- Ensure the new per-host secret directories exist:
  - `secrets/profiles/personal/desktops/tux-h4xx-01/`
  - `secrets/profiles/personal/desktops/tab-h4xx-02/`
  - `secrets/profiles/personal/servers/srv4-vm-01/`
  - `secrets/profiles/personal/servers/smc-gpu-01/`
  - `secrets/profiles/work/desktops/macbook-pro/`
  - `secrets/profiles/work/servers/docker-host-01/`
  - `secrets/profiles/work/servers/timebutler-test-vm/`
  - `secrets/profiles/common/shared/` for cross-profile SSH/GPG/API tokens
  - Run `sops secrets/profiles/work/servers/docker-host-01/root-password.hash` (and similar) to confirm encryption uses the intended recipient.
  - Re-encrypt any plain-text files with `sops --encrypt --in-place …` so they pick up the new Age recipient rules.
  - Update/commit any host-specific secrets under the matching directory; keep cross-profile material in `secrets/profiles/common/shared/`.

## 3. Codex CLI & Neovim Integration
- Ensure `OPENAI_API_KEY` is available. Home Manager decrypts `openai.env` into `~/.config/secrets/openai.env` and shells source it automatically; keep that secret up to date or override it manually:
  - Add `export OPENAI_API_KEY=…` to `.bash_profile` / `.bashrc`.
  - Use `direnv` with `.envrc` to scope the key per-repo.
  - Inject it at runtime via `op run --env-file`, `pass`, or similar secret managers.
- Run `codex --help` to verify the CLI works; try `codex "summarize git status"`.
- In Neovim:
  - Start `nvim`, run `:Codex ask for a summary of this project`.
  - Visually select code, trigger `<leader>ca` and inspect the floating buffer.
  - Launch the interactive terminal with `<leader>cT` (alias `:CodexTerminal`).
- Review `docs/neovim-cheatsheet.md` and keep it accessible (e.g., pinned in your workspace docs).

## 4. VS Code Updates
- Open VS Code and ensure the Codex terminal profile is available (Terminal → New Terminal → “Codex”).
- Press `Ctrl + Alt + C` to spawn the Codex terminal using the keybinding.
- Verify GitHub Copilot & Copilot Chat extensions are installed and activated.

## 5. Git Alias Completions
- Start a new bash session to pull in updated completion scripts.
- Type `k <TAB>` and confirm kubectl subcommands complete.
- Test `tf <TAB>` for terraform, and `dc <TAB>` for docker compose.
- If completions fail, recheck `~/.bash/alias-completions.sh` sourcing.

## 6. Repository Hygiene
- `git status` should list all new files staged when ready; add any stragglers.
- Run `nix flake check --no-write-lock-file --extra-experimental-features 'nix-command flakes'` before committing (expect only “dirty tree / incompatible systems” warnings).
- Commit with a descriptive message (e.g., “Integrate Codex CLI & Flux K9s hotkeys”).

## 7. Follow-ups / Ideas
- Consider adding K9s hotkeys for Flux GitRepositories if used.
- Evaluate alias completion coverage after adding new shell aliases.
- Update the cheat sheet periodically when leader mappings change.
