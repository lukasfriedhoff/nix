{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardwareProfiles.tuxedo.infinitybookPro16Gen8;
in
{
  options.hardwareProfiles.tuxedo.infinitybookPro16Gen8 = {
    enable = lib.mkEnableOption "TUXEDO InfinityBook Pro 16 Gen8 hardware profile";
  };

  config = lib.mkIf cfg.enable {
    # Firmware & platform services
    hardware.enableAllFirmware = true;
    services.fwupd.enable = true;
    # TUXEDO OS runs power-profiles-daemon alongside tccd.
    services.power-profiles-daemon.enable = lib.mkDefault true;
    services.thermald.enable = true;
    services.hardware.bolt.enable = true;
    services.logind.settings.Login.KillUserProcesses = false;

    hardware.sensor.iio.enable = true;
    hardware.bluetooth.enable = true;
    # Mirror TUXEDO OS kernel module stack (tuxedo_keyboard + related modules).
    hardware.tuxedo-drivers.enable = true;

    hardware.tuxedo-rs = {
      enable = false; # Use tccd instead for full TDP/fan/cTGP control
      tailor-gui.enable = false;
    };

    # TUXEDO OS uses kernel/systemd backlight handling, not acpilight.
    hardware.acpilight.enable = lib.mkForce false;

    # Match TUXEDO OS NetworkManager defaults for Intel CNVi Wi-Fi.
    networking.networkmanager.wifi = {
      powersave = lib.mkDefault true;
      scanRandMacAddress = lib.mkDefault false;
    };
    # Match TUXEDO OS GRUB kernel verbosity defaults.
    boot.kernelParams = [
      "loglevel=3"
      "udev.log_level=3"
    ];

    # Graphics: Intel iGPU + NVIDIA RTX 4070 Max-Q (01:00.0)
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver
        intel-vaapi-driver
        libva-vdpau-driver
        libvdpau-va-gl
      ];
    };

    hardware.nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      powerManagement.finegrained = false; # Incompatible with PRIME sync
      open = true; # Use open driver like Tuxedo OS
      dynamicBoost.enable = true; # Enable nvidia-powerd for CPU/GPU power balancing
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      prime = {
        offload.enable = false;
        sync.enable = true; # Use dGPU for all rendering (better gaming perf)
        intelBusId = "PCI:0:2:0";
        nvidiaBusId = "PCI:1:0:0";
      };
    };

    # Match TUXEDO OS sysctl defaults.
    boot.kernel.sysctl = {
      "vm.swappiness" = 10;
      "vm.max_map_count" = lib.mkForce 1048576;
    };

    services.xserver.videoDrivers = [
      "nvidia"
      "modesetting"
    ];

    boot.blacklistedKernelModules = [
      "nouveau"
      "snd-mixer-oss"
      "snd-pcm-oss"
    ];

    environment.systemPackages = with pkgs; [
      mesa-demos # provides glxinfo for quick renderer checks
      nvtopPackages.intel
      powertop
    ];

    programs.gamemode.enable = true;
  };
}
