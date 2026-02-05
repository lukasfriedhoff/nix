{
  config,
  lib,
  ...
}:

let
  cfg = config.lukasf.wolf;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    optional
    types
    ;

  mkIndented = lines: lib.concatStringsSep "\n" (map (line: "    ${line}") lines);

  baseVolumes = [
    "/dev/:/dev/:rw"
    "/run/udev:/run/udev:rw"
    "${cfg.configDir}:/etc/wolf:z"
    "/run/podman/podman.sock:/var/run/docker.sock:ro"
  ];

  baseDevices = [
    "/dev/dri"
    "/dev/uinput"
    "/dev/uhid"
  ];

  baseEnvironment = [
    "WOLF_STOP_CONTAINER_ON_EXIT=TRUE"
  ];
in
{
  options.lukasf.wolf = {
    enable = mkEnableOption "Wolf (Games on Whales) container";

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the Wolf ports in the firewall.";
    };

    configDir = mkOption {
      type = types.str;
      default = "/etc/wolf";
      description = "Directory on the host for Wolf configuration files.";
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/games-on-whales/wolf:stable";
      description = "Container image for Wolf.";
    };

    network = mkOption {
      type = types.str;
      default = "host";
      description = "Podman network mode for the Wolf container.";
    };

    autoUpdate = mkOption {
      type = types.nullOr types.str;
      default = "registry";
      description = "Quadlet AutoUpdate policy (set null to disable).";
    };

    podmanArgs = mkOption {
      type = types.nullOr types.str;
      default = "--ipc=host --device-cgroup-rule \"c 13:* rmw\"";
      description = "Extra Podman arguments for the container (single string).";
    };

    securityLabelDisable = mkOption {
      type = types.bool;
      default = true;
      description = "Disable SELinux labeling for the container.";
    };

    extraDevices = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional devices passed via AddDevice=.";
    };

    extraVolumes = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional volumes passed via Volume=.";
    };

    extraEnvironment = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional environment variables (KEY=VALUE).";
    };

    preRemoveContainers = mkOption {
      type = types.listOf types.str;
      default = [ "WolfPulseAudio" ];
      description = "Container names removed before starting Wolf.";
    };

    timeoutStartSec = mkOption {
      type = types.int;
      default = 900;
      description = "Timeout in seconds before the unit is considered failed.";
    };

    restartSec = mkOption {
      type = types.int;
      default = 5;
      description = "Delay in seconds before restarting the unit.";
    };

    startLimitBurst = mkOption {
      type = types.int;
      default = 5;
      description = "Start limit burst for the unit.";
    };

    ports = {
      https = mkOption {
        type = types.port;
        default = 47984;
        description = "HTTPS port (WOLF_HTTPS_PORT).";
      };
      http = mkOption {
        type = types.port;
        default = 47989;
        description = "HTTP port (WOLF_HTTP_PORT).";
      };
      control = mkOption {
        type = types.port;
        default = 47999;
        description = "UDP control port (WOLF_CONTROL_PORT).";
      };
      rtsp = mkOption {
        type = types.port;
        default = 48010;
        description = "RTSP setup port (WOLF_RTSP_SETUP_PORT).";
      };
      video = mkOption {
        type = types.port;
        default = 48100;
        description = "UDP video ping port (WOLF_VIDEO_PING_PORT).";
      };
      audio = mkOption {
        type = types.port;
        default = 48200;
        description = "UDP audio ping port (WOLF_AUDIO_PING_PORT).";
      };
    };
  };

  config = mkIf cfg.enable {
    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [
        cfg.ports.https
        cfg.ports.http
        cfg.ports.rtsp
      ];
      allowedUDPPorts = [
        cfg.ports.control
        cfg.ports.video
        cfg.ports.audio
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.configDir} 0755 root root -"
    ];

    environment.etc."containers/systemd/wolf.container".text =
      let
        serviceLines = mkIndented (
          [
            "TimeoutStartSec=${toString cfg.timeoutStartSec}"
          ]
          ++ map (
            name: "ExecStartPre=-/run/current-system/sw/bin/podman rm --force ${name}"
          ) cfg.preRemoveContainers
          ++ [
            "Restart=on-failure"
            "RestartSec=${toString cfg.restartSec}"
            "StartLimitBurst=${toString cfg.startLimitBurst}"
          ]
        );

        containerLines = mkIndented (
          [
            "ContainerName=%p"
            "HostName=%p"
            "Image=${cfg.image}"
            "Network=${cfg.network}"
          ]
          ++ optional (cfg.autoUpdate != null) "AutoUpdate=${cfg.autoUpdate}"
          ++ optional cfg.securityLabelDisable "SecurityLabelDisable=true"
          ++ optional (cfg.podmanArgs != null && cfg.podmanArgs != "") "PodmanArgs=${cfg.podmanArgs}"
          ++ map (device: "AddDevice=${device}") (baseDevices ++ cfg.extraDevices)
          ++ map (volume: "Volume=${volume}") (baseVolumes ++ cfg.extraVolumes)
          ++ map (entry: "Environment=${entry}") (baseEnvironment ++ cfg.extraEnvironment)
        );
      in
      ''
                [Unit]
                Description=Wolf / Games On Whales
                Requires=network-online.target podman.socket
                After=network-online.target podman.socket

                [Service]
        ${serviceLines}

                [Container]
        ${containerLines}

                [Install]
                WantedBy=multi-user.target
      '';
  };
}
