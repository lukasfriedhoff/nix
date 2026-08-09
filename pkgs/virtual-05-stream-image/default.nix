{
  lib,
  bash,
  coreutils,
  dbus,
  dockerTools,
  mesa,
  procps,
  sunshine,
  writeShellApplication,
  writeTextFile,
  xfce4-session,
  xfce4-panel,
  xfwm4,
  xorg-server,
  xdpyinfo,
  xf86-video-dummy,

  # Kept as arguments so the image can be retargeted without editing it.
  resolution ? "1920x1080",
  modeLine ? ''Modeline "1920x1080" 148.50 1920 2448 2492 2640 1080 1084 1089 1125 +hsync +vsync'',
  vaapiDevice ? "/dev/dri/renderD128",
  tag ? "latest",
}:

let
  # Same virtual-framebuffer trick the NixOS module uses: a container has no
  # seat and no CRTC, so there is nothing for Sunshine to capture until Xorg
  # provides an offscreen screen.
  xorgConf = writeTextFile {
    name = "xorg-dummy.conf";
    text = ''
      # xf86-video-dummy is a separate store path, so Xorg's built-in module
      # path does not cover it and the server exits with "no screens found".
      # Both paths are required: the server's own modules plus the driver's.
      Section "Files"
        ModulePath "${xorg-server}/lib/xorg/modules"
        ModulePath "${xf86-video-dummy}/lib/xorg/modules/drivers"
      EndSection

      Section "ServerFlags"
        Option "AutoAddDevices" "false"
        Option "DontVTSwitch"   "true"
      EndSection

      Section "Monitor"
        Identifier  "dummy-monitor"
        HorizSync   5.0 - 200.0
        VertRefresh 5.0 - 200.0
        ${modeLine}
      EndSection

      Section "Device"
        Identifier "dummy-device"
        Driver     "dummy"
        VideoRam   256000
      EndSection

      Section "Screen"
        Identifier   "dummy-screen"
        Device       "dummy-device"
        Monitor      "dummy-monitor"
        DefaultDepth 24
        SubSection "Display"
          Depth 24
          Modes "${resolution}"
        EndSubSection
      EndSection
    '';
  };

  # Deliberately not systemd. Kubernetes wants to supervise one process, and a
  # full init inside a pod needs privileged mode plus cgroup access. Xorg and
  # the session are started as children; Sunshine is exec'd last so it becomes
  # PID 1's foreground process and its exit takes the pod down.
  entrypoint = writeShellApplication {
    name = "virtual-05-stream";
    runtimeInputs = [
      bash
      coreutils
      dbus
      procps
      sunshine
      xfce4-session
      xorg-server
      xdpyinfo
      xf86-video-dummy
    ];
    text = ''
      set -euo pipefail

      export DISPLAY="''${DISPLAY:-:0}"
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/tmp/xdg-runtime}"
      mkdir -p "$XDG_RUNTIME_DIR"
      chmod 0700 "$XDG_RUNTIME_DIR"

      # mesa here, not on the host: srv8 is a server config with no graphics
      # stack, so radeonsi_drv_video.so only exists inside this image.
      export LIBVA_DRIVERS_PATH="''${LIBVA_DRIVERS_PATH:-${mesa}/lib/dri}"
      export LIBVA_DRIVER_NAME="''${LIBVA_DRIVER_NAME:-radeonsi}"

      # Mesa's GBM loader hardcodes NixOS's /run/opengl-driver, which only
      # exists on a NixOS host. Without this Sunshine reports
      # "Couldn't create GBM device" and silently drops to libx264 — the
      # stream still works, just without the GPU we picked srv8 for.
      export GBM_BACKENDS_PATH="''${GBM_BACKENDS_PATH:-${mesa}/lib/gbm}"

      # Some of the stack still looks at the NixOS path directly, so provide
      # it rather than relying on every consumer honouring the env vars.
      if [ ! -e /run/opengl-driver ]; then
        mkdir -p /run
        ln -sfn ${mesa} /run/opengl-driver 2>/dev/null || true
      fi

      if [ ! -e "${vaapiDevice}" ]; then
        echo "warning: ${vaapiDevice} is missing; Sunshine will fall back to software encoding" >&2
      fi

      cleanup() {
        [ -n "''${XORG_PID:-}" ] && kill "$XORG_PID" 2>/dev/null || true
        [ -n "''${SESSION_PID:-}" ] && kill "$SESSION_PID" 2>/dev/null || true
      }
      trap cleanup EXIT INT TERM

      # A dockerTools image has no /var/log and no writable /tmp/.X11-unix, and
      # Xorg treats an unopenable log as fatal rather than falling back.
      mkdir -p /tmp/.X11-unix "$XDG_RUNTIME_DIR/xorg"
      chmod 1777 /tmp/.X11-unix

      Xorg "$DISPLAY" \
        -config ${xorgConf} \
        -logfile "$XDG_RUNTIME_DIR/xorg/Xorg.0.log" \
        -noreset &
      XORG_PID=$!

      # Poll rather than sleep a fixed amount: Xorg readiness varies with how
      # busy the node is, and starting the session too early leaves a desktop
      # with no screen.
      for _ in $(seq 1 100); do
        if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then break; fi
        if ! kill -0 "$XORG_PID" 2>/dev/null; then
          echo "Xorg exited before the display came up" >&2
          exit 1
        fi
        sleep 0.2
      done
      xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || {
        echo "timed out waiting for $DISPLAY" >&2
        exit 1
      }

      # /etc/dbus-1/session.conf in the image is a dangling symlink into a
      # different dbus output than the one that got layered in, so the daemon
      # reads nothing and dies on "needs one or more <listen> elements".
      # Point at the config in this closure instead of trusting /etc.
      dbus-run-session --config-file=${dbus}/share/dbus-1/session.conf -- xfce4-session &
      SESSION_PID=$!

      exec sunshine
    '';
  };
in
dockerTools.buildLayeredImage {
  name = "virtual-05-stream";
  inherit tag;

  contents = [
    bash
    coreutils
    dbus
    entrypoint
    mesa
    sunshine
    xfce4-session
    xfce4-panel
    xfwm4
    xorg-server
    xdpyinfo
    xf86-video-dummy
    dockerTools.caCertificates
    # Without /etc/passwd dbus cannot resolve its own UID and dies with a
    # misleading "Memory allocation failure in message bus".
    dockerTools.fakeNss
  ];

  config = {
    Entrypoint = [ (lib.getExe entrypoint) ];
    Env = [
      "DISPLAY=:0"
      "LIBVA_DRIVERS_PATH=${mesa}/lib/dri"
      "LIBVA_DRIVER_NAME=radeonsi"
      "GBM_BACKENDS_PATH=${mesa}/lib/gbm"
    ];
    ExposedPorts = {
      # Web UI, then the Moonlight control/stream ports.
      "47990/tcp" = { };
      "47984/tcp" = { };
      "47989/tcp" = { };
      "48010/tcp" = { };
      "47998/udp" = { };
      "47999/udp" = { };
      "48000/udp" = { };
      "48002/udp" = { };
    };
  };

  meta = {
    description = "Headless XFCE desktop with Sunshine, for streaming to Moonlight from Kubernetes";
    platforms = lib.platforms.linux;
  };
}
