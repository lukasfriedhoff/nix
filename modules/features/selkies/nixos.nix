{
  config,
  lib,
  pkgs,
  ...
}:

# Browser-based desktop streaming (WebSocket transport), sibling of
# lukasf.sunshine: the same Xorg-dummy headless pattern, but the client is a
# web page instead of Moonlight. Selkies attaches to the user's existing
# graphical session; capture is XShm, input is XTEST (uinput only for
# gamepads), audio arrives through the PulseAudio protocol that
# pipewire-pulse already serves.
let
  cfg = config.lukasf.selkies;

  dummyMonitor = ''
    Section "Monitor"
      Identifier "selkies-dummy"
      HorizSync   ${cfg.headless.horizSync}
      VertRefresh ${cfg.headless.vertRefresh}
      ${cfg.headless.modeLine}
    EndSection

    Section "Device"
      Identifier "selkies-dummy-device"
      Driver     "dummy"
      VideoRam   ${toString cfg.headless.videoRamKb}
    EndSection

    Section "Screen"
      Identifier  "selkies-dummy-screen"
      Device      "selkies-dummy-device"
      Monitor     "selkies-dummy"
      DefaultDepth 24
      SubSection "Display"
        Depth     24
        Modes     "${cfg.headless.resolution}"
      EndSubSection
    EndSection
  '';
in
{
  options.lukasf.selkies = {
    enable = lib.mkEnableOption "Selkies browser-based desktop streaming";

    package = lib.mkPackageOption pkgs "selkies" { };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "HTTP/WebSocket port of the streaming server.";
    };

    public = lib.mkEnableOption "binding on all interfaces instead of loopback only";

    openFirewall = lib.mkEnableOption "open the streaming port in the firewall";

    basicAuth = {
      enable = lib.mkEnableOption "selkies' own basic auth" // {
        default = true;
      };
      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Environment file providing SELKIES_BASIC_AUTH_PASSWORD (sops
          secret, readable by the session user). Selkies refuses to start
          with basic auth enabled and no password set.
        '';
      };
    };

    wayland = {
      enable = lib.mkEnableOption "Wayland capture instead of X11";

      nested = lib.mkEnableOption ''
        letting selkies run the capture compositor with the session
        compositor nested inside it as a client, instead of capturing an
        external compositor directly. Input and clipboard are auto-routed
        to the nested compositor's own socket. Prefer this: importing
        pixelflux's dmabufs into wlroots fails with EGL_BAD_MATCH, so
        direct capture of a wlroots session produces no frames at all
      '';
      hostDisplay = lib.mkOption {
        type = lib.types.str;
        default = "auto";
        description = ''
          WAYLAND_DISPLAY socket of the compositor pixelflux attaches to as
          a client (screencopy capture, virtual keyboard/pointer input).
          "auto" probes wayland-1 then wayland-0 in XDG_RUNTIME_DIR at
          service start.
        '';
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        encoder = "h264enc";
      };
      description = "Extra settings rendered as SELKIES_<NAME> environment variables.";
    };

    headless = {
      enable = lib.mkEnableOption "an Xorg dummy virtual display for headless capture" // {
        default = true;
      };

      resolution = lib.mkOption {
        type = lib.types.str;
        default = "1920x1080";
        description = "Virtual display resolution.";
      };

      modeLine = lib.mkOption {
        type = lib.types.str;
        default = ''Modeline "1920x1080" 148.50 1920 2448 2492 2640 1080 1084 1089 1125 +hsync +vsync'';
        description = "Modeline matching {option}`resolution`.";
      };

      horizSync = lib.mkOption {
        type = lib.types.str;
        default = "5.0 - 200.0";
        description = "Dummy monitor horizontal sync range, in kHz.";
      };

      vertRefresh = lib.mkOption {
        type = lib.types.str;
        default = "5.0 - 200.0";
        description = "Dummy monitor vertical refresh range, in Hz.";
      };

      videoRamKb = lib.mkOption {
        type = lib.types.int;
        default = 256000;
        description = "Dummy driver framebuffer size in KB (must exceed width*height*4).";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "lukasf";
        description = "User automatically logged in to own the streamed session.";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.basicAuth.enable -> cfg.basicAuth.environmentFile != null;
            message = "lukasf.selkies: basic auth is enabled but no environmentFile provides SELKIES_BASIC_AUTH_PASSWORD (the server refuses to start without one).";
          }
        ];

        systemd.user.services.selkies = {
          description = "Selkies desktop streaming server";
          wantedBy = [ "graphical-session.target" ];
          partOf = [ "graphical-session.target" ];
          after = [ "graphical-session.target" ];
          environment = {
            SELKIES_PORT = toString cfg.port;
            SELKIES_PUBLIC = lib.boolToString cfg.public;
          }
          // lib.optionalAttrs cfg.wayland.enable (
            {
              SELKIES_WAYLAND = "true";
            }
            # Nested: no host display at all — selkies composites, and
            # app_wayland_display auto-detects the nested socket.
            // lib.optionalAttrs (!cfg.wayland.nested && cfg.wayland.hostDisplay != "auto") {
              SELKIES_WAYLAND_HOST_DISPLAY = cfg.wayland.hostDisplay;
            }
          )
          // lib.optionalAttrs (!cfg.basicAuth.enable) { SELKIES_ENABLE_BASIC_AUTH = "false"; }
          // lib.mapAttrs' (n: v: lib.nameValuePair "SELKIES_${lib.toUpper n}" v) cfg.settings;
          serviceConfig = {
            ExecStart =
              if cfg.wayland.enable && !cfg.wayland.nested && cfg.wayland.hostDisplay == "auto" then
                pkgs.writeShellScript "selkies-wayland-auto" ''
                  # The compositor's socket index is not deterministic
                  # (wayland-0 or wayland-1 depending on what raced first);
                  # probe rather than hardcode.
                  for _ in $(seq 1 50); do
                    for s in wayland-1 wayland-0; do
                      if [ -S "$XDG_RUNTIME_DIR/$s" ]; then
                        # Both: HOST_DISPLAY is the capture target, and
                        # WAYLAND_DISPLAY is what the input/clipboard client
                        # connects to.
                        export SELKIES_WAYLAND_HOST_DISPLAY="$s"
                        export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-$s}"
                        exec ${lib.getExe cfg.package}
                      fi
                    done
                    sleep 0.2
                  done
                  echo "no wayland socket appeared in $XDG_RUNTIME_DIR" >&2
                  exit 1
                ''
              else
                lib.getExe cfg.package;
            Restart = "on-failure";
            RestartSec = 3;
          }
          // lib.optionalAttrs (cfg.basicAuth.environmentFile != null) {
            EnvironmentFile = cfg.basicAuth.environmentFile;
          };
        };

        # Gamepads reach applications through uinput; keyboard/mouse are
        # injected via XTEST and need nothing extra.
        boot.kernelModules = [ "uinput" ];
        hardware.uinput.enable = lib.mkDefault true;
        users.users.${cfg.headless.user}.extraGroups = lib.mkAfter [
          "input"
          "video"
          "render"
        ];

        # radeonsi/iHD userspace; the render node alone is not enough.
        hardware.graphics.enable = lib.mkDefault true;

        # Desktop audio flows browser-ward through the monitor of this null
        # sink; pcmflux speaks the PulseAudio protocol pipewire-pulse serves.
        # The name is not cosmetic: selkies captures "output.monitor" and
        # creates its own sink named "output" when it finds none, which then
        # competes with a differently-named one for the default.
        services.pipewire.extraConfig.pipewire."60-selkies-null-sink" = {
          "context.objects" = [
            {
              factory = "adapter";
              args = {
                "factory.name" = "support.null-audio-sink";
                "node.name" = "output";
                "node.description" = "Selkies stream output";
                "media.class" = "Audio/Sink";
                "priority.session" = 2000;
                "audio.position" = "FL,FR";
              };
            }
            # The microphone half: what the browser sends arrives here, and
            # applications record from it.
            {
              factory = "adapter";
              args = {
                "factory.name" = "support.null-audio-sink";
                "node.name" = "input";
                "node.description" = "Selkies stream input";
                "media.class" = "Audio/Source/Virtual";
                "audio.position" = "FL,FR";
              };
            }
          ];
        };

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
      }

      (lib.mkIf cfg.headless.enable {
        services.xserver = {
          enable = lib.mkDefault true;
          videoDrivers = lib.mkDefault [ "dummy" ];
          extraConfig = dummyMonitor;
        };

        # GDM expects a seat and a TTY, neither of which exists in a
        # container; autologin gives the user service a session to join.
        services.displayManager = {
          gdm.enable = lib.mkForce false;
          autoLogin = {
            enable = lib.mkDefault true;
            user = lib.mkDefault cfg.headless.user;
          };
        };
      })
    ]
  );
}
