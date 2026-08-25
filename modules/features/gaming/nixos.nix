{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.desktop.gaming;
in
{
  options.desktop.gaming = {
    enable = lib.mkEnableOption "Steam/Proton gaming stack";

    nvidiaBusId = lib.mkOption {
      type = lib.types.str;
      default = "1";
      description = ''
        DRM card number of the NVIDIA GPU for GameMode GPU optimizations.
        This is the number in /sys/class/drm/cardN, not the PRIME PCI bus ID.
      '';
      example = "1";
    };

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

    fpsLimit = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 60;
      description = ''
        FPS limit for MangoHud. Set to null to disable.
        For VRR displays, use ~97% of refresh rate (e.g., 140 for 144Hz).
        For fixed 60Hz displays, 60 is fine to save GPU power.
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
      with pkgs;
      [
        mangohud
        goverlay
        vkbasalt
        protontricks
        lutris
        wineWow64Packages.full
        discord
        steam-tui
        steamGameWrapper
        ludusavi # Game save backup tool
        config.hardware.nvidia.package.settings
      ];

    environment.sessionVariables = {
      # NVIDIA/Proton compatibility
      PROTON_ENABLE_NVAPI = "1";
      DXVK_NVAPI_ALLOW_OTHER_DRIVERS = "1";
      PROTON_EAC_RUNTIME = "1";
      VKD3D_CONFIG = "dxr11";

      # Proton enhancements
      # Wine's Wayland driver stays off: with NVIDIA + DLSS it segfaulted
      # (Icarus, 2026-08-25, wine64-preloader SIGSEGV), and borderless mode
      # loses its resolution/display picker. XWayland is the stable path;
      # re-evaluate when Proton's Wayland driver leaves experimental.
      PROTON_ENABLE_WAYLAND = "0";
      PROTON_ENABLE_HDR = "1"; # HDR support (when display supports it)
      PROTON_USE_NTSYNC = "1"; # Better Wine synchronization
      PROTON_USE_WOW64 = "1"; # Improved 32-bit game compatibility

      # FSR/upscaling
      WINE_FULLSCREEN_FSR = "1";

      # MangoHud default off (enable per-game or via steam-game wrapper)
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
          gpu_device = cfg.nvidiaBusId;
          amd_performance_level = "high";
        };
        custom = {
          start = "${pkgs.libnotify}/bin/notify-send -i input-gaming 'GameMode' 'Optimizations enabled'";
          end = "${pkgs.libnotify}/bin/notify-send -i input-gaming 'GameMode' 'Optimizations disabled'";
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
      # DRM permissions
      ACTION=="add", SUBSYSTEM=="drm", RUN+="${pkgs.coreutils}/bin/chmod 0660 /dev/dri/card0"

      # ntsync support for PROTON_USE_NTSYNC (kernel 6.14+)
      KERNEL=="ntsync", MODE="0660", TAG+="uaccess"

      # PlayStation controller motion sensor disable (prevents input conflicts)
      ACTION=="add|change", SUBSYSTEM=="input", ATTRS{name}=="*Motion Sensors", ENV{LIBINPUT_IGNORE_DEVICE}="1"
    '';

    services.envfs.enable = true;

    # Kernel parameters for reduced overhead
    boot.kernelParams = [ "nowatchdog" ];

    boot.kernel.sysctl = {
      # Memory mapping for games with large assets
      "vm.max_map_count" = 2147483642;
      # Scheduler tuning for gaming workloads
      "kernel.sched_migration_cost_ns" = 5000000;
      # Disable watchdogs to reduce CPU overhead
      "kernel.nmi_watchdog" = 0;
      "kernel.soft_watchdog" = 0;
    };

    # MangoHud configuration
    environment.etc."mangohud.conf".text = ''
      # Performance overlay
      fps
      frametime
      cpu_stats
      cpu_temp
      gpu_stats
      gpu_temp
      gpu_power
      ram
      vram

      # Position and style
      position=top-left
      font_size=20
      background_alpha=0.4
      round_corners=5

      # Toggle keybinds
      toggle_hud=Shift_R+F12
      toggle_fps_limit=Shift_R+F1
    ''
    + lib.optionalString (cfg.fpsLimit != null) ''

      # FPS limit (97% of refresh for VRR, or match display Hz)
      fps_limit=${toString cfg.fpsLimit}
    '';
  };
}
