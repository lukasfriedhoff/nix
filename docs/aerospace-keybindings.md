# AeroSpace keybindings (MacBook Pro)

Main mode (default)
- Alt+/ toggles tiling layouts; Alt+, toggles accordion layouts
- Alt-h/j/k/l focuses left/down/up/right; Alt-Shift-h/j/k/l moves the focused window
- Alt-Shift-- shrinks / Alt-Shift-= grows the focused pane
- Alt-1..4 jump to workspaces on the primary display; Alt-5..9 jump to workspaces on the secondary display
- Alt-Shift-1..9 move the focused window to the target workspace; Alt-f fullscreen; Alt-Shift-f toggles floating
- Alt-Shift-; enters service mode

Service mode (Alt-Shift-;)
- Esc reloads the config and exits service mode
- r flattens the workspace tree and returns to main mode
- Alt-Shift-h/j/k/l joins the current container with the neighbor in that direction, then returns to main mode

Startup and multi-monitor notes
- AeroSpace is set to start at login via the Home Manager launchd service
- Workspaces 1-4 are pinned to the main display; 5-9 are pinned to the secondary display via `workspace-to-monitor-force-assignment`; adjust patterns if your monitor ordering differs
- SketchyBar auto-starts via the AeroSpace `after-startup-command` hook

Karabiner option
- If you prefer easier modifiers, install `karabiner-elements` and map Caps Lock to a Hyper key for the AeroSpace shortcuts
