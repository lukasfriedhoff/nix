{
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ../../common/default.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "tab-h4xx-02";

  hardwareProfiles.asus.vivobookT3300.enable = true;
  boot.initrd.luks.devices."luks-3ec9fc7f-dba1-4c81-9eb0-255731e15fd6".device =
    "/dev/disk/by-uuid/3ec9fc7f-dba1-4c81-9eb0-255731e15fd6";
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  boot.kernelParams = [ "sdhci.debug_quirks=0x20000" ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  services.openssh.settings.PasswordAuthentication = false;

  environment.systemPackages = with pkgs; [
    adwaita-icon-theme
    dmidecode
    lm_sensors
  ];

  desktop.wireguardHomelab = {
    enable = true;
    address = "10.1.90.3/24";
  };

  # Enable gaming support for the ASUS Vivobook
  desktop.gaming = {
    enable = true;
  };

  # Prefer RAM compression over eMMC swap to cut thrashing
  zramSwap = {
    enable = true;
    memoryPercent = 150;
    algorithm = "zstd";
    priority = 100;
  };

  # Bias swapping toward zram before touching eMMC
  boot.kernel.sysctl."vm.swappiness" = 80;

  # Trim and power tuning for the low-power SoC and eMMC
  services.fstrim.enable = true;
  powerManagement.powertop.enable = false;

  # Trim GNOME background services on 4 GB RAM devices
  services.gnome = {
    localsearch.enable = false;
    tinysparql.enable = false;
    gnome-online-accounts.enable = lib.mkForce false;
    evolution-data-server.enable = lib.mkForce false;
  };

  # Disable GNOME animations for snappier UI
  services.desktopManager.gnome.extraGSettingsOverrides = ''
    [org.gnome.desktop.interface]
    enable-animations=false
  '';

  # Ensure redistributable firmware + Intel microcode are applied
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.intel.updateMicrocode = lib.mkForce true;
}
