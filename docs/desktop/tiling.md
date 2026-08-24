# Tiling window management (Sway + AeroSpace)

One logical keybinding set drives both platforms, defined once in
[`modules/features/desktop/tiling/def.nix`](../../modules/features/desktop/tiling/def.nix):
AeroSpace on macOS renders it with `alt`, Sway on Linux with `Super`
(`desktop.sway.modifier = "alt"` switches Linux to alt at the cost of
colliding with in-app Alt shortcuts). Tune a binding there and both
platforms follow.

## Core bindings (`MOD` = alt on macOS, Super on Linux)

| Keys | Action |
|---|---|
| `MOD+h/j/k/l` | focus left/down/up/right |
| `MOD+Shift+h/j/k/l` | move window |
| `MOD+1..9` / `MOD+Shift+1..9` | switch / move to workspace |
| `MOD+Tab` | back-and-forth between last two workspaces |
| `MOD+slash` | toggle tiles horizontal/vertical |
| `MOD+comma` | accordion (macOS) / tabbed-stacking (Linux) |
| `MOD+f` / `MOD+Shift+f` | fullscreen / float toggle |
| `MOD+Shift+minus / equal` | resize |
| `MOD+Shift+;` | service mode (Escape reloads config) |

Linux-only: `MOD+Return` terminal (alacritty), `MOD+d` launcher (wofi),
`MOD+Shift+q` close window, `MOD+v`/`MOD+b` split vertical/horizontal,
`Print` full-screen screenshot, `Shift+Print` region screenshot (both to
`~/Pictures/screenshots/` and the clipboard), `MOD+Print` region
screenshot opened in swappy for annotation, `` MOD+` `` quake-style
dropdown terminal (floating, centered, toggles via scratchpad),
`MOD+p` clipboard-history picker (cliphist + wofi, includes images).

## Nested layouts ("one window left, two stacked right")

- **AeroSpace** has no split command by design. Focus the middle window,
  `alt+Shift+;` then `alt+Shift+l` (`join-with right`); normalization
  flips the nested container vertical. `alt+Shift+;` then `r` flattens.
- **Sway**: focus the right window, `Super+v`, open the third window.

## NVIDIA note

On NVIDIA-rendered hosts (`desktop.sway.nvidiaUnsupportedGpu = true`)
Sway starts with `--unsupported-gpu` and prints a proprietary-driver
warning at launch. That is expected: wlroots does not vouch for the
proprietary driver; the flag opts in anyway. Harmless in practice on
recent drivers — occasional artifacts after driver updates are the trade.

## Per-host outputs

Workspace-to-monitor pinning on Linux is per-host (`swaymsg -t
get_outputs` for names, then `wayland.windowManager.sway.config.workspaceOutputAssign`
in the host's HM config). macOS pinning lives in the shared def
(main/secondary).

## Session services (Sway only)

All bound to `sway-session.target`, so a parallel GNOME login is
unaffected:

- **kanshi** — output profiles on hotplug; hosts define
  `services.kanshi.settings` (tux: `docked`/`mobile`).
- **autotiling** — alternates split direction based on the focused
  window's shape; closest match to AeroSpace's automatic tiling.
- **cliphist** — clipboard history daemon behind `MOD+p`.
- **swayosd** — on-screen bars for the volume/brightness keys (the keys
  call `swayosd-client`, which changes the value and draws the OSD;
  backlight access comes from swayosd's udev rule + `video` group).
- **gammastep** — night light (6500K day / 4200K night).
- **workspace-autoname** — renames workspaces to `N: term web ...` in
  waybar; switching stays number-based (`workspace number N`).
