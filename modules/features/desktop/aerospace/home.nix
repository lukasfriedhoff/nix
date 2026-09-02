# AeroSpace tiling window manager for macOS.
# Uses the built-in home-manager programs.aerospace module.
# Keybindings come from the shared tiling definition so the Sway session
# on the Linux desktops mirrors them (alt here, Super there); tune both
# in modules/features/desktop/tiling/def.nix.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.aerospace;
  tiling = import ../tiling/def.nix { inherit lib; };
  renderKey = tiling.renderKey {
    prefix = "alt";
    sep = "-";
    shift = "shift";
    keyNames = { };
  };
  mainBindings = lib.filterAttrs (_: cmd: cmd != null) (
    lib.mapAttrs' (key: cmds: lib.nameValuePair (renderKey key) cmds.aerospace) tiling.mainBindings
  );
  # esc and r are deliberately unprefixed inside service mode.
  serviceBindings = lib.filterAttrs (_: cmd: cmd != null) (
    lib.mapAttrs' (
      key: cmds:
      lib.nameValuePair (
        if
          lib.elem key [
            "esc"
            "r"
          ]
        then
          key
        else
          renderKey key
      ) cmds.aerospace
    ) tiling.serviceBindings
  );
in
{
  config = lib.mkMerge [
    {
      programs.aerospace.enable = lib.mkDefault pkgs.stdenv.isDarwin;
    }
    (lib.mkIf (cfg.enable && pkgs.stdenv.isDarwin) {
      programs.aerospace.launchd.enable = lib.mkDefault true;

      programs.aerospace.settings = lib.mkDefault {
        # Config schema version required for persistent workspaces, etc.
        config-version = 2;

        # Normalizations
        enable-normalization-flatten-containers = true;
        enable-normalization-opposite-orientation-for-nested-containers = true;

        # Accordion layout padding
        accordion-padding = 30;

        # Default root container
        default-root-container-layout = "tiles";
        default-root-container-orientation = "auto";

        # Launch + startup (managed by Home Manager launchd)
        start-at-login = true;
        # SketchyBar starts via its own Home Manager launchd service.
        after-startup-command = [ ];

        # Keep SketchyBar's workspace indicator in sync.
        exec-on-workspace-change = lib.mkIf config.programs.sketchybar.enable [
          "/bin/bash"
          "-c"
          "${lib.getExe config.programs.sketchybar.package} --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE"
        ];

        # Keep workspace IDs alive even if empty
        persistent-workspaces = tiling.workspaces;

        # Pin workspaces to monitors (main = primary display, secondary = the other one)
        workspace-to-monitor-force-assignment =
          lib.genAttrs tiling.mainMonitorWorkspaces (_: "main")
          // lib.genAttrs tiling.secondaryMonitorWorkspaces (_: "secondary");

        # Gaps between windows and screen edges
        gaps = {
          inner.horizontal = 10;
          inner.vertical = 10;
          outer.left = 10;
          outer.right = 10;
          outer.bottom = 10;
          outer.top = [
            { monitor.main = 10; }
            { monitor.secondary = 24; }
            10
          ];
        };

        # i3-like bindings, shared with Sway via tiling/def.nix
        mode.main.binding = mainBindings;

        # Service mode for reload and tree operations (join-with builds
        # nested splits: focus a window, alt-shift-semicolon, then
        # alt-shift-h/j/k/l to join it with the neighbour in that direction)
        mode.service.binding = serviceBindings;
      };
    })
  ];
}
