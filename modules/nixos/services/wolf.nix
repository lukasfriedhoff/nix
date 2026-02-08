{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.wolf;
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optional
    types
    ;

  tomlFormat = pkgs.formats.toml { };
  configDirCfg = "${cfg.configDir}/cfg";
  configFile = "${configDirCfg}/config.toml";

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
    "HOST_APPS_STATE_FOLDER=${cfg.configDir}"
    "WOLF_CFG_FILE=${configFile}"
    "WOLF_STOP_CONTAINER_ON_EXIT=TRUE"
  ];

  defaultAppCatalog = {
    ui = {
      title = "Wolf UI";
      icon_png_path = "https://raw.githubusercontent.com/games-on-whales/wolf-ui/refs/heads/main/src/Icons/wolf_ui_icon.png";
      start_virtual_compositor = true;
      runner = {
        type = "docker";
        name = "Wolf-UI";
        image = "ghcr.io/games-on-whales/wolf-ui:main";
        mounts = [
          "/var/run/wolf/wolf.sock:/var/run/wolf/wolf.sock"
        ];
        env = [
          "GOW_REQUIRED_DEVICES=/dev/input/event* /dev/dri/* /dev/nvidia*"
          "WOLF_SOCKET_PATH=/var/run/wolf/wolf.sock"
          "WOLF_UI_AUTOUPDATE=False"
          "LOGLEVEL=INFO"
        ];
        devices = [ ];
        ports = [ ];
        base_create_json = ''
          {
            "HostConfig": {
              "IpcMode": "host",
              "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_ADMIN", "SYS_NICE"],
              "Privileged": false,
              "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
            }
          }
        '';
      };
    };
    testBall = {
      title = "Test ball";
      icon_png_path = "https://raw.githubusercontent.com/games-on-whales/wolf/refs/heads/stable/docs/images/test_ball_icon.png";
      start_audio_server = false;
      start_virtual_compositor = false;
      runner = {
        type = "process";
        run_cmd = "sh -c \"while :; do echo 'running...'; sleep 10; done\"";
      };
      audio = {
        source = "audiotestsrc wave=ticks is-live=true";
      };
      video = {
        source = "videotestsrc pattern=ball flip=true is-live=true !\nvideo/x-raw, framerate={fps}/1\n";
      };
    };
    firefox = {
      title = "Firefox";
      icon_png_path = "https://games-on-whales.github.io/wildlife/apps/firefox/assets/icon.png";
      start_virtual_compositor = true;
      runner = {
        type = "docker";
        name = "WolfFirefox";
        image = "ghcr.io/games-on-whales/firefox:edge";
        mounts = [ ];
        env = [
          "RUN_SWAY=1"
          "MOZ_ENABLE_WAYLAND=1"
          "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
        ];
        devices = [ ];
        ports = [ ];
        base_create_json = ''
          {
            "HostConfig": {
              "IpcMode": "host",
              "Privileged": false,
              "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN"],
              "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
            }
          }
        '';
      };
    };
    retroarch = {
      title = "RetroArch";
      icon_png_path = "https://games-on-whales.github.io/wildlife/apps/retroarch/assets/icon.png";
      start_virtual_compositor = true;
      runner = {
        type = "docker";
        name = "WolfRetroarch";
        image = "ghcr.io/games-on-whales/retroarch:edge";
        mounts = [ ];
        env = [
          "RUN_SWAY=true"
          "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
        ];
        devices = [ ];
        ports = [ ];
        base_create_json = ''
          {
            "HostConfig": {
              "IpcMode": "host",
              "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_ADMIN", "SYS_NICE"],
              "Privileged": false,
              "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
            }
          }
        '';
      };
    };
    steam = {
      title = "Steam";
      icon_png_path = "https://games-on-whales.github.io/wildlife/apps/steam/assets/icon.png";
      start_virtual_compositor = true;
      runner = {
        type = "docker";
        name = "WolfSteam";
        image = "ghcr.io/games-on-whales/steam:edge";
        mounts = [ ];
        env = [
          "PROTON_LOG=1"
          "RUN_SWAY=true"
          "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
        ];
        devices = [ ];
        ports = [ ];
        base_create_json = ''
          {
            "HostConfig": {
              "IpcMode": "host",
              "CapAdd": ["SYS_ADMIN", "SYS_NICE", "SYS_PTRACE", "NET_RAW", "MKNOD", "NET_ADMIN"],
              "SecurityOpt": ["seccomp=unconfined", "apparmor=unconfined"],
              "Ulimits": [{"Name":"nofile", "Hard":10240, "Soft":10240}],
              "Privileged": false,
              "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
            }
          }
        '';
      };
    };
    pegasus = {
      title = "Pegasus";
      icon_png_path = "https://games-on-whales.github.io/wildlife/apps/pegasus/assets/icon.png";
      start_virtual_compositor = true;
      runner = {
        type = "docker";
        name = "WolfPegasus";
        image = "ghcr.io/games-on-whales/pegasus:edge";
        mounts = [ ];
        env = [
          "RUN_SWAY=1"
          "GOW_REQUIRED_DEVICES=/dev/input/event* /dev/dri/* /dev/nvidia*"
        ];
        devices = [ ];
        ports = [ ];
        base_create_json = ''
          {
            "HostConfig": {
              "IpcMode": "host",
              "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_ADMIN", "SYS_NICE"],
              "Privileged": false,
              "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
            }
          }
        '';
      };
    };
    lutris = {
      title = "Lutris";
      icon_png_path = "https://games-on-whales.github.io/wildlife/apps/lutris/assets/icon.png";
      start_virtual_compositor = true;
      runner = {
        type = "docker";
        name = "WolfLutris";
        image = "ghcr.io/games-on-whales/lutris:edge";
        mounts = [
          "lutris:/var/lutris/:rw"
        ];
        env = [
          "RUN_SWAY=1"
          "GOW_REQUIRED_DEVICES=/dev/input/event* /dev/dri/* /dev/nvidia* /var/lutris/"
        ];
        devices = [ ];
        ports = [ ];
        base_create_json = ''
          {
            "HostConfig": {
              "IpcMode": "host",
              "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_ADMIN", "SYS_NICE"],
              "Privileged": false,
              "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
            }
          }
        '';
      };
    };
    prismlauncher = {
      title = "Prismlauncher";
      icon_png_path = "https://games-on-whales.github.io/wildlife/apps/prismlauncher/assets/icon.png";
      start_virtual_compositor = true;
      runner = {
        type = "docker";
        name = "Prismlauncher";
        image = "ghcr.io/games-on-whales/prismlauncher:edge";
        mounts = [ ];
        env = [
          "RUN_SWAY=1"
          "GOW_REQUIRED_DEVICES=/dev/input/event* /dev/dri/* /dev/nvidia* /var/lutris/"
        ];
        devices = [ ];
        ports = [ ];
        base_create_json = ''
          {
            "HostConfig": {
              "IpcMode": "host",
              "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_ADMIN", "SYS_NICE"],
              "Privileged": false,
              "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
            }
          }
        '';
      };
    };
    desktop = {
      title = "Desktop (xfce)";
      icon_png_path = "https://games-on-whales.github.io/wildlife/apps/xfce/assets/icon.png";
      runner = {
        type = "docker";
        name = "WolfXFCE";
        image = "ghcr.io/games-on-whales/xfce:edge";
        mounts = [ ];
        env = [
          "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
        ];
        devices = [ ];
        ports = [ ];
        base_create_json = ''
          {
            "HostConfig": {
              "IpcMode": "host",
              "Privileged": false,
              "CapAdd": ["SYS_ADMIN", "SYS_NICE", "SYS_PTRACE", "NET_RAW", "MKNOD", "NET_ADMIN"],
              "SecurityOpt": ["seccomp=unconfined", "apparmor=unconfined"],
              "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
            }
          }
        '';
      };
    };
    emulationstation = {
      title = "EmulationStation";
      icon_png_path = "https://games-on-whales.github.io/wildlife/apps/es-de/assets/icon.png";
      runner = {
        type = "docker";
        name = "WolfES-DE";
        image = "ghcr.io/games-on-whales/es-de:edge";
        mounts = [ ];
        env = [
          "RUN_SWAY=1"
          "MOZ_ENABLE_WAYLAND=1"
          "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
        ];
        devices = [ ];
        ports = [ ];
        base_create_json = ''
          {
            "HostConfig": {
              "IpcMode": "host",
              "Privileged": false,
              "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN"],
              "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
            }
          }
        '';
      };
    };
    kodi = {
      title = "Kodi";
      icon_png_path = "https://games-on-whales.github.io/wildlife/apps/kodi/assets/icon.png";
      runner = {
        type = "docker";
        name = "WolfKodi";
        image = "ghcr.io/games-on-whales/kodi:edge";
        mounts = [ ];
        env = [
          "RUN_SWAY=true"
          "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
        ];
        devices = [ ];
        ports = [ ];
        base_create_json = ''
          {
            "HostConfig": {
              "IpcMode": "host",
              "Privileged": false,
              "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN"],
              "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
            }
          }
        '';
      };
    };
    icarusModManager = {
      title = "Icarus Mod Manager";
      start_virtual_compositor = true;
      app_state_folder = "icarus-mod-manager";
      runner = {
        type = "docker";
        name = "WolfIcarusModManager";
        image = "localhost/wolf-icarus-mod-manager:latest";
        mounts = [ ];
        env = [
          "RUN_SWAY=1"
          "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
        ];
        devices = [ ];
        ports = [ ];
        base_create_json = ''
          {
            "HostConfig": {
              "IpcMode": "host",
              "Privileged": false,
              "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN"],
              "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
            }
          }
        '';
      };
    };
  };

  effectiveCatalog = defaultAppCatalog // cfg.appCatalog;

  resolvedProfiles = map (
    profile:
    let
      resolvedApps = map (name: effectiveCatalog.${name}) profile.appNames;
      extraApps = profile.apps;
      baseProfile = lib.removeAttrs profile [
        "appNames"
        "apps"
        "name"
      ];
      nameAttr = lib.optionalAttrs (profile.name != null) { name = profile.name; };
    in
    baseProfile // nameAttr // { apps = resolvedApps ++ extraApps; }
  ) cfg.profiles;

  mergedSettings = lib.recursiveUpdate cfg.settings (
    lib.optionalAttrs (cfg.profiles != [ ]) {
      profiles = resolvedProfiles;
    }
  );

  missingAppNames = lib.unique (
    lib.concatLists (
      map (profile: lib.filter (name: !(lib.hasAttr name effectiveCatalog)) profile.appNames) cfg.profiles
    )
  );

  configFileSource =
    if cfg.configText != null then
      pkgs.writeText "wolf-config.toml" cfg.configText
    else if mergedSettings != { } then
      tomlFormat.generate "wolf-config.toml" mergedSettings
    else
      null;

  manageConfig = configFileSource != null;

  python = pkgs.python3.withPackages (ps: [ ps.tomli-w ]);

  preserveArgs = lib.escapeShellArgs cfg.preserveKeys;

  mergeScript =
    if manageConfig then
      pkgs.writeShellScript "wolf-config-merge" ''
                set -euo pipefail
                src="${configFileSource}"
                dst="${configFile}"
                install -d -m 0755 "$(dirname "$dst")"
                if [ ! -f "$dst" ]; then
                  install -m 0644 "$src" "$dst"
                  exit 0
                fi
                ${python}/bin/python - "$src" "$dst" ${preserveArgs} <<'PY'
        import sys
        import uuid
        from pathlib import Path

        import tomllib
        import tomli_w

        src = Path(sys.argv[1])
        dst = Path(sys.argv[2])
        preserve = set(sys.argv[3:])

        with src.open("rb") as handle:
            new_config = tomllib.load(handle)

        existing_config = {}
        if dst.exists():
            with dst.open("rb") as handle:
                existing_config = tomllib.load(handle)

        for key in preserve:
            if key in existing_config:
                new_config[key] = existing_config[key]

        if "uuid" in preserve and "uuid" not in new_config:
            new_config["uuid"] = str(uuid.uuid4())

        if "paired_clients" in preserve and "paired_clients" not in new_config:
            new_config["paired_clients"] = []

        if "config_version" not in new_config:
            new_config["config_version"] = 2

        with dst.open("wb") as handle:
            tomli_w.dump(new_config, handle)
        PY
      ''
    else
      null;

  podmanBin = "${pkgs.podman}/bin/podman";
  bashBin = "${pkgs.bash}/bin/bash";

  sanitizeServiceName =
    name:
    lib.replaceStrings
      [
        "/"
        ":"
        "."
        "@"
      ]
      [
        "-"
        "-"
        "-"
        "-"
      ]
      name;

  mkImageService =
    image:
    let
      serviceName = "wolf-image-${sanitizeServiceName image.name}";
      buildCmd = "${podmanBin} build -t ${lib.escapeShellArg image.name} -f ${lib.escapeShellArg image.dockerfile} ${lib.escapeShellArg image.context}";
      script =
        if image.alwaysBuild then
          buildCmd
        else
          "if ! ${podmanBin} image exists ${lib.escapeShellArg image.name}; then ${buildCmd}; fi";
    in
    lib.optionalAttrs image.autoBuild {
      "${serviceName}" = {
        description = "Build Wolf app image ${image.name}";
        after = [
          "network-online.target"
          "podman.socket"
        ];
        wants = [
          "network-online.target"
          "podman.socket"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${bashBin} -c ${lib.escapeShellArg script}";
        };
        wantedBy = [ "multi-user.target" ];
      };
    };
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

    settings = mkOption {
      type = tomlFormat.type;
      default = { };
      description = "Base TOML configuration written to ${configFile}.";
    };

    configText = mkOption {
      type = types.nullOr types.lines;
      default = null;
      description = "Raw TOML configuration content (overrides settings).";
    };

    appCatalog = mkOption {
      type = types.attrsOf types.attrs;
      default = defaultAppCatalog;
      description = "Catalog of Wolf app definitions keyed by name.";
    };

    profiles = mkOption {
      type = types.listOf (
        types.submodule ({
          freeformType = types.attrs;
          options = {
            id = mkOption {
              type = types.str;
              description = "Profile identifier stored in the Wolf config.";
            };

            name = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Optional profile display name.";
            };

            appNames = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Names of apps from appCatalog to attach to this profile.";
            };

            apps = mkOption {
              type = types.listOf types.attrs;
              default = [ ];
              description = "Inline app definitions appended after appNames.";
            };
          };
        })
      );
      default = [ ];
      description = "Profiles assembled from appCatalog selections.";
    };

    preserveKeys = mkOption {
      type = types.listOf types.str;
      default = [
        "uuid"
        "paired_clients"
        "hostname"
        "config_version"
        "support_hevc"
        "gstreamer"
      ];
      description = "Config keys preserved from the existing file when regenerating.";
    };

    appImages = mkOption {
      type = types.listOf (
        types.submodule (
          { config, ... }:
          {
            options = {
              name = mkOption {
                type = types.str;
                description = "Podman image tag for the Wolf app image.";
              };

              dockerfile = mkOption {
                type = types.path;
                description = "Path to the Dockerfile used to build the image.";
              };

              context = mkOption {
                type = types.path;
                default = null;
                description = "Build context directory (defaults to the Dockerfile directory).";
              };

              autoBuild = mkOption {
                type = types.bool;
                default = true;
                description = "Build the image automatically via systemd.";
              };

              alwaysBuild = mkOption {
                type = types.bool;
                default = false;
                description = "Rebuild the image every time the systemd unit runs.";
              };
            };

            config = {
              context = lib.mkDefault (builtins.dirOf config.dockerfile);
            };
          }
        )
      );
      default = [ ];
      description = "Local Wolf app images built with Podman.";
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
    lukasf.wolf.appCatalog = lib.mkDefault defaultAppCatalog;

    assertions = map (name: {
      assertion = lib.hasAttr name cfg.appCatalog;
      message = "lukasf.wolf.appCatalog is missing app '${name}'";
    }) missingAppNames;

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
      "d ${configDirCfg} 0755 root root -"
      "d ${cfg.configDir}/profile_data 0755 root root -"
    ];

    system.activationScripts.wolfConfig = mkIf manageConfig ''
      ${mergeScript}
    '';

    systemd.services = mkMerge (map mkImageService cfg.appImages);

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
