{
  lib,
  bash,
  coreutils,
  dbus,
  dockerTools,
  mesa,
  procps,
  pulseaudio,
  selkies,
  writeShellApplication,
  writeTextFile,
  xfce4-session,
  xfce4-panel,
  xfce4-terminal,
  xfwm4,
  xorg-server,
  xdpyinfo,
  xf86-video-dummy,

  # Kept as arguments so the image can be retargeted without editing it.
  resolution ? "1920x1080",
  modeLine ? ''Modeline "1920x1080" 148.50 1920 2448 2492 2640 1080 1084 1089 1125 +hsync +vsync'',
  tag ? "latest",
}:

let
  # Same virtual-framebuffer trick as virtual-05-stream-image: a pod has no
  # seat and no CRTC, so Xorg's dummy driver provides the screen pixelflux
  # captures via XShm.
  xorgConf = writeTextFile {
    name = "xorg-dummy.conf";
    text = ''
      # xf86-video-dummy is a separate store path, so Xorg's built-in module
      # path does not cover it and the server exits with "no screens found".
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

  entrypoint = writeShellApplication {
    name = "selkies-desktop";
    runtimeInputs = [
      bash
      coreutils
      dbus
      procps
      pulseaudio
      selkies
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

      # XFCE and selkies both want a writable HOME; a pod provides none.
      export HOME="''${HOME:-/tmp/home}"
      mkdir -p "$HOME"

      # VA-API/GBM plumbing as in virtual-05-stream-image: the k3s hosts are
      # server configs without a graphics stack, so the userspace drivers only
      # exist inside this image. Without a GPU pixelflux falls back to CPU
      # striped encoding on its own.
      export LIBVA_DRIVERS_PATH="''${LIBVA_DRIVERS_PATH:-${mesa}/lib/dri}"
      export LIBVA_DRIVER_NAME="''${LIBVA_DRIVER_NAME:-radeonsi}"
      export GBM_BACKENDS_PATH="''${GBM_BACKENDS_PATH:-${mesa}/lib/gbm}"
      if [ ! -e /run/opengl-driver ]; then
        mkdir -p /run
        ln -sfn ${mesa} /run/opengl-driver 2>/dev/null || true
      fi

      cleanup() {
        [ -n "''${XORG_PID:-}" ] && kill "$XORG_PID" 2>/dev/null || true
        [ -n "''${SESSION_PID:-}" ] && kill "$SESSION_PID" 2>/dev/null || true
        [ -n "''${PULSE_PID:-}" ] && kill "$PULSE_PID" 2>/dev/null || true
      }
      trap cleanup EXIT INT TERM

      mkdir -p /tmp/.X11-unix "$XDG_RUNTIME_DIR/xorg" "$XDG_RUNTIME_DIR/pulse"
      chmod 1777 /tmp/.X11-unix

      Xorg "$DISPLAY" \
        -config ${xorgConf} \
        -logfile "$XDG_RUNTIME_DIR/xorg/Xorg.0.log" \
        -noreset &
      XORG_PID=$!

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

      # Selkies captures the monitor of the default sink through pcmflux and
      # plays the microphone into the default source, so the null sinks are
      # the audio path, not a leftover: "output" carries desktop audio to the
      # browser, "input" is what apps record from.
      export PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native"
      pulseaudio --daemonize=no --exit-idle-time=-1 -n \
        --load="module-native-protocol-unix socket=$XDG_RUNTIME_DIR/pulse/native auth-anonymous=1" \
        --load="module-null-sink sink_name=output sink_properties=device.description=selkies-output" \
        --load="module-null-sink sink_name=input sink_properties=device.description=selkies-input" \
        --log-target=stderr &
      PULSE_PID=$!
      for _ in $(seq 1 50); do
        if pactl info >/dev/null 2>&1; then break; fi
        sleep 0.2
      done
      pactl set-default-sink output || true
      pactl set-default-source output.monitor || true

      # dbus config path pinned for the same dangling-symlink reason as in
      # virtual-05-stream-image.
      dbus-run-session --config-file=${dbus}/share/dbus-1/session.conf -- xfce4-session &
      SESSION_PID=$!

      # Refuses to start until a password arrives via PASSWORD (or basic auth
      # is explicitly disabled) — the safe default for a cluster-facing pod.
      exec selkies
    '';
  };
in
dockerTools.buildLayeredImage {
  name = "selkies-desktop";
  inherit tag;

  contents = [
    bash
    coreutils
    dbus
    entrypoint
    mesa
    pulseaudio
    selkies
    xfce4-session
    xfce4-panel
    xfce4-terminal
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
      # Bind all interfaces: the pod is reached through a Service, and auth
      # is selkies' own basic auth (password injected by the Deployment).
      "SELKIES_PUBLIC=true"
      "SELKIES_PORT=8080"
    ];
    ExposedPorts = {
      "8080/tcp" = { };
    };
  };

  meta = {
    description = "Headless XFCE desktop streamed to the browser by Selkies, for Kubernetes";
    platforms = lib.platforms.linux;
  };
}
