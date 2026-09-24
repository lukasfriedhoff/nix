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
    # VA-API support for Jasper Lake iGPU
    extraPackages = [ pkgs.intel-media-driver ];
  };
  boot.kernelParams = [ "sdhci.debug_quirks=0x20000" ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  services.openssh.settings.PasswordAuthentication = false;

  # sshd was enabled with PasswordAuthentication off and no authorized keys at
  # all, which meant nothing could ever log in - the tablet had to be handled
  # physically. Authorize tux so it can be rebuilt and deployed remotely like
  # every other host.
  #
  # root as well as lukasf: `security.sudo.wheelNeedsPassword` is true here, so
  # `nixos-rebuild --target-host lukasf@… --sudo` would sit waiting on a
  # password prompt. Deploying as root avoids that, and root login is already
  # key-only.
  users.users.lukasf.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEUMr5wOTPNvoAQHFmUNAXc1N31RkweWxRotw471S23M lukasf"
  ];
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEUMr5wOTPNvoAQHFmUNAXc1N31RkweWxRotw471S23M lukasf"
  ];

  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

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
