{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.desktop.laptop;
in
{
  options.desktop.laptop = {
    enable = lib.mkEnableOption "laptop power management profile" // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    # Laptop-specific power management and optimizations.
    # Import this profile on mobile devices (laptops, tablets).

    # Power management
    powerManagement = {
      enable = true;
      powertop.enable = true;
    };

    # TLP for advanced power management (alternative to auto-cpufreq)
    # Disabled by default - enable if auto-cpufreq doesn't work well for your hardware
    services.tlp = {
      enable = lib.mkDefault false;
      settings = {
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
        CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
        CPU_BOOST_ON_AC = 1;
        CPU_BOOST_ON_BAT = 0;
        WIFI_PWR_ON_AC = "off";
        WIFI_PWR_ON_BAT = "on";
      };
    };

    # auto-cpufreq for dynamic CPU frequency scaling
    # Disabled by default since it conflicts with power-profiles-daemon
    services.auto-cpufreq = {
      enable = lib.mkDefault false;
      settings = {
        battery = {
          governor = "powersave";
          turbo = "never";
        };
        charger = {
          governor = "performance";
          turbo = "auto";
        };
      };
    };

    # Thermald for Intel thermal management
    services.thermald.enable = lib.mkDefault true;

    # Power profiles daemon for GNOME/KDE integration (preferred over auto-cpufreq)
    services.power-profiles-daemon.enable = lib.mkDefault true;

    # WiFi power saving
    networking.networkmanager.wifi.powersave = lib.mkDefault true;

    # Periodic TRIM for SSD longevity
    services.fstrim = {
      enable = true;
      interval = "weekly";
    };

    # Reduce disk writes
    boot.kernel.sysctl = {
      # Increase dirty page writeback time for better batching
      "vm.dirty_writeback_centisecs" = lib.mkDefault 6000;
      # Reduce journal commits
      "vm.laptop_mode" = lib.mkDefault 5;
    };

    # Backlight control
    programs.light.enable = lib.mkDefault true;

    # Power monitoring tools
    environment.systemPackages = with pkgs; [
      powertop
      acpi
    ];
  };
}
