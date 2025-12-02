{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.desktop.gaming;
  nvidiaBusId = "PCI:1:0:0";
in
{
  options.desktop.gaming = {
    enable = lib.mkEnableOption "Steam/Proton gaming stack";

    defaultRenderer = lib.mkOption {
      type = lib.types.enum [
        "intel"
        "nvidia"
      ];
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

    environment.systemPackages =
      let
        steamGameWrapper = pkgs.writeShellScriptBin "steam-game" ''
          set -euo pipefail
          if [ $# -lt 1 ]; then
            echo "usage: steam-game <steam-app-id> [extra steam args]" >&2
            exit 1
          fi

          appid="$1"
          shift || true

          cmd=( steam -applaunch "$appid" "$@" )

          if [ ''${USE_MANGOHUD:-1} != 0 ]; then
            cmd=( mangohud ''${cmd[@]} )
          fi

          if [ ''${USE_GAMEMODE:-0} != 0 ]; then
            export GAMEMODEAUTO="${pkgs.gamemode}/lib/libgamemodeauto.so.0"
            cmd=( gamemoderun ''${cmd[@]} )
          fi

          ${lib.optionalString (cfg.defaultRenderer == "intel") ''
            export __NV_PRIME_RENDER_OFFLOAD=1
            export __GLX_VENDOR_LIBRARY_NAME=nvidia
            export __VK_LAYER_NV_optimus=NVIDIA_only
          ''}

          exec ''${cmd[@]}
        '';
      in
      with pkgs; [
        mangohud
        goverlay
        vkbasalt
        protontricks
        lutris
        wineWowPackages.full
        discord
        steam-tui
        steamGameWrapper
      ];

    environment.sessionVariables = {
      PROTON_ENABLE_NVAPI = "1";
      DXVK_NVAPI_ALLOW_OTHER_DRIVERS = "1";
      PROTON_EAC_RUNTIME = "1";
      WINE_FULLSCREEN_FSR = "1";
      VKD3D_CONFIG = "dxr11";
      MANGOHUD = "0";
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
