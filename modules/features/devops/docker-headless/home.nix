{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.dockerHeadless;

  defaultColimaSettings = {
    inherit (cfg) cpu;
    inherit (cfg) memory;
    inherit (cfg) disk;
    arch = "host";
    runtime = "docker";
    autoActivate = true;
    kubernetes.enabled = cfg.kubernetes.enable;
  };
in
{
  options.programs.dockerHeadless = {
    enable = lib.mkEnableOption "headless Docker runtime on macOS using Colima";

    package = lib.mkPackageOption pkgs "colima" { };

    cpu = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "CPU cores assigned to the Colima VM.";
    };

    memory = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "Memory in GiB assigned to the Colima VM.";
    };

    disk = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100;
      description = "Disk size in GiB assigned to the Colima VM.";
    };

    startAtLogin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start the Colima Docker runtime with a user LaunchAgent.";
    };

    extraSettings = lib.mkOption {
      inherit ((pkgs.formats.yaml { })) type;
      default = { };
      example = lib.literalExpression ''
        {
          vmType = "vz";
          mountType = "virtiofs";
        }
      '';
      description = "Extra Colima profile settings merged into the default profile.";
    };

    kubernetes.enable = lib.mkEnableOption "Kubernetes in the default Colima profile";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isDarwin;
        message = "programs.dockerHeadless is intended for macOS; use Docker or Podman modules on Linux.";
      }
    ];

    home.packages = [
      pkgs.docker-client
      pkgs.docker-compose
      pkgs.docker-buildx
      pkgs.docker-credential-helpers
      pkgs.lima
    ];

    programs.docker-cli = {
      enable = true;
      configDir = "${config.xdg.configHome}/docker";
      settings = {
        credsStore = lib.mkDefault "osxkeychain";
        features.buildkit = true;
      };
    };

    services.colima = {
      enable = true;
      colimaHomeDir = "${config.xdg.configHome}/colima";
      inherit (cfg) package;
      dockerPackage = pkgs.docker-client;
      profiles.default = {
        isActive = true;
        isService = cfg.startAtLogin;
        setDockerHost = true;
        settings = lib.recursiveUpdate defaultColimaSettings cfg.extraSettings;
      };
    };

    programs.bash.shellAliases = {
      docker-start = "colima start";
      docker-stop = "colima stop";
      docker-status = "colima status";
      docker-logs = "tail -f ${config.xdg.stateHome}/colima/default.log";
    };
  };
}
