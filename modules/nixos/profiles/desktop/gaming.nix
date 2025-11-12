{ config, lib, pkgs, ... }:

let
  cfg = config.desktop.gaming;
  nvidiaBusId = "PCI:1:0:0";
in
{
  options.desktop.gaming = {
    enable = lib.mkEnableOption "Steam/Proton gaming stack";

    defaultRenderer = lib.mkOption {
      type = lib.types.enum [ "intel" "nvidia" ];
      default = "nvidia";
      example = "intel";
      description = ''
        Select which GL/Vulkan implementation should back the desktop session.
        Use "intel" to keep compositor/applications on the iGPU and rely on
        `nvidia-offload` / PRIME variables for discrete GPU workloads.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.graphics.enable = true;
    hardware.graphics.enable32Bit = true;

    environment.systemPackages = with pkgs; [
      mangohud
      goverlay
      vkbasalt
      protontricks
      lutris
      wineWowPackages.full
      discord
    ];

    environment.sessionVariables =
      {
        PROTON_ENABLE_NVAPI = "1";
        DXVK_NVAPI_ALLOW_OTHER_DRIVERS = "1";
        PROTON_EAC_RUNTIME = "1";
        WINE_FULLSCREEN_FSR = "1";
        VKD3D_CONFIG = "dxr11";
        MANGOHUD = "1";
        GAMEMODERUNEXEC = "1";
      }
      // lib.optionalAttrs (cfg.defaultRenderer == "nvidia") {
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      }
      // lib.optionalAttrs (cfg.defaultRenderer == "intel") {
        __GLX_VENDOR_LIBRARY_NAME = "modesetting";
      };

    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = true;
      extraCompatPackages = with pkgs; [
        proton-ge-bin
      ];
    };

    programs.gamemode = {
      enable = true;
      settings = {
        general = {
          renice = 5;
        };
        gpu = {
          apply_gpu_optimisations = "accept-responsibility";
          gpu_device = nvidiaBusId;
          amd_performance_level = "high";
        };
      };
    };

    programs.gamescope = {
      enable = true;
      capSysNice = true;
      args = [
        "-f"
        "-W 1920"
        "-H 1080"
        "-r 60"
        "--hdr-enabled"
      ];
    };

    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="drm", RUN+="${pkgs.coreutils}/bin/chmod 0660 /dev/dri/card0"
    '';

    services.envfs.enable = true;

    boot.kernel.sysctl = {
      "vm.max_map_count" = 2147483642;
      "kernel.sched_migration_cost_ns" = 5000000;
    };
  };
}
