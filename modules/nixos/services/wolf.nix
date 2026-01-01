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
    mkOption
    optional
    optionalAttrs
    types
    ;

  defaultBackend = if config.virtualisation.podman.enable then "podman" else "docker";

  dockerSocketPath =
    if cfg.backend == "docker" then "/var/run/docker.sock" else "/run/podman/podman.sock";
in
{
  options.lukasf.wolf = {
    enable = mkEnableOption "Wolf streaming server container";

    backend = mkOption {
      type = types.enum [
        "podman"
        "docker"
      ];
      default = defaultBackend;
      description = ''
        Container backend used for the Wolf service. Podman runs rootful with
        Docker compatibility so the Wolf container can access `/var/run/docker.sock`.
      '';
    };

    image = mkOption {
      type = types.str;
      default = "ghcr.io/games-on-whales/wolf:stable";
      description = "Container image to run.";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/wolf";
      description = "Host directory bound to /etc/wolf inside the container.";
    };

    createEtcSymlink = mkOption {
      type = types.bool;
      default = true;
      description = "Create /etc/wolf -> stateDir symlink for convenience on the host.";
    };

    dockerSocket = mkOption {
      type = types.str;
      default = dockerSocketPath;
      defaultText = ''if backend == "docker" then "/var/run/docker.sock" else "/run/podman/podman.sock"'';
      description = ''
        Host socket path for the container runtime. This is always exposed to
        the Wolf container as /var/run/docker.sock.
      '';
    };

    renderNode = mkOption {
      type = types.str;
      default = "/dev/dri/renderD128";
      description = "Render node passed via WOLF_RENDER_NODE.";
    };

    nvidia = {
      mode = mkOption {
        type = types.enum [
          "disabled"
          "toolkit"
          "driverVolume"
        ];
        default = "disabled";
        description = ''
          How to expose Nvidia devices. Use "toolkit" for nvidia-container-toolkit
          (adds --gpus=all) or "driverVolume" to mount an external driver volume
          like in the upstream manual instructions.
        '';
      };

      driverVolumeName = mkOption {
        type = types.str;
        default = "nvidia-driver-vol";
        description = "Volume name containing Nvidia driver files (driverVolume mode only).";
      };
    };

    extraVolumes = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional volume bindings for the Wolf container.";
    };

    extraOptions = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Extra raw container options appended to oci-containers.";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment variables passed to the Wolf container.";
    };
  };

  config = mkIf cfg.enable {
    boot.kernelModules = lib.mkAfter [
      "uinput"
      "uhid"
    ];

    services.udev.extraRules = ''
      # Virtual device support as recommended by the Wolf quickstart docs
      KERNEL=="uinput", SUBSYSTEM=="misc", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput", TAG+="uaccess"
      KERNEL=="uhid", GROUP="input", MODE="0660", TAG+="uaccess"

      # Virtual pads exposed by Wolf
      KERNEL=="hidraw*", ATTRS{name}=="Wolf PS5 (virtual) pad", GROUP="input", MODE="0660", ENV{ID_SEAT}="seat9"
      SUBSYSTEMS=="input", ATTRS{name}=="Wolf X-Box One (virtual) pad", MODE="0660", ENV{ID_SEAT}="seat9"
      SUBSYSTEMS=="input", ATTRS{name}=="Wolf PS5 (virtual) pad", MODE="0660", ENV{ID_SEAT}="seat9"
      SUBSYSTEMS=="input", ATTRS{name}=="Wolf gamepad (virtual) motion sensors", MODE="0660", ENV{ID_SEAT}="seat9"
      SUBSYSTEMS=="input", ATTRS{name}=="Wolf Nintendo (virtual) pad", MODE="0660", ENV{ID_SEAT}="seat9"
    '';

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 root root -"
      "d ${cfg.stateDir}/cfg 0750 root root -"
      "d ${cfg.stateDir}/profile_data 0750 root root -"
    ]
    ++ optional cfg.createEtcSymlink "L /etc/wolf - - - - ${cfg.stateDir}";

    virtualisation.oci-containers.backend = cfg.backend;

    virtualisation.podman = mkIf (cfg.backend == "podman") {
      enable = true;
      dockerCompat = lib.mkDefault true;
    };

    virtualisation.docker.enable = mkIf (cfg.backend == "docker") true;

    virtualisation.oci-containers.containers.wolf = {
      autoStart = true;
      image = cfg.image;

      volumes = [
        "${cfg.stateDir}:/etc/wolf:rw"
        "${cfg.dockerSocket}:/var/run/docker.sock:rw"
        "/dev:/dev:rw"
        "/run/udev:/run/udev:rw"
      ]
      ++ optional (cfg.nvidia.mode == "driverVolume") "${cfg.nvidia.driverVolumeName}:/usr/nvidia:rw"
      ++ cfg.extraVolumes;

      extraOptions = [
        "--network=host"
        "--device=/dev/dri"
        "--device=/dev/uinput"
        "--device=/dev/uhid"
        "--device-cgroup-rule=c 13:* rmw"
      ]
      ++ (
        if cfg.nvidia.mode == "toolkit" then
          [ "--gpus=all" ]
        else if cfg.nvidia.mode == "driverVolume" then
          [
            "--device=/dev/nvidia-uvm"
            "--device=/dev/nvidia-uvm-tools"
            "--device=/dev/nvidiactl"
            "--device=/dev/nvidia-modeset"
            "--device=/dev/nvidia0"
            "--device=/dev/nvidia-caps/nvidia-cap1"
            "--device=/dev/nvidia-caps/nvidia-cap2"
          ]
        else
          [ ]
      )
      ++ cfg.extraOptions;

      environment = {
        WOLF_CFG_FILE = "/etc/wolf/cfg/config.toml";
        WOLF_PRIVATE_KEY_FILE = "/etc/wolf/cfg/key.pem";
        WOLF_PRIVATE_CERT_FILE = "/etc/wolf/cfg/cert.pem";
        WOLF_DOCKER_SOCKET = "/var/run/docker.sock";
        WOLF_RENDER_NODE = cfg.renderNode;
      }
      // optionalAttrs (cfg.nvidia.mode == "toolkit") {
        NVIDIA_DRIVER_CAPABILITIES = "all";
        NVIDIA_VISIBLE_DEVICES = "all";
      }
      // optionalAttrs (cfg.nvidia.mode == "driverVolume") {
        NVIDIA_DRIVER_VOLUME_NAME = cfg.nvidia.driverVolumeName;
      }
      // cfg.environment;
    };
  };
}
