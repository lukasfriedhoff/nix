{ config, pkgs, secrets, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/hardware/asus/vivobook-t3300.nix
  ];


  networking.hostName = "tab-h4xx-02";
  boot.initrd.luks.devices."luks-3ec9fc7f-dba1-4c81-9eb0-255731e15fd6".device = "/dev/disk/by-uuid/3ec9fc7f-dba1-4c81-9eb0-255731e15fd6";
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
    smartmontools
  ];

  sops.secrets."wireguard-homelab-priv" = {
    sopsFile = "${secrets.primary}/wireguard/homelab.priv";
    owner = "root";
    format = "binary";
  };
  sops.secrets."wireguard-domain" = {
    sopsFile = "${secrets.shared}/wireguard/domain.txt";
    owner = "root";
    format = "binary";
  };
  sops.secrets."wireguard-endpoint" = {
    sopsFile = "${secrets.shared}/wireguard/endpoint.txt";
    owner = "root";
    format = "binary";
  };

  lukasf.wireguard.homelab = {
    enable = false;
    address = "10.1.90.3/24";
    privateKeyFile = config.sops.secrets."wireguard-homelab-priv".path;
    dnsDomainFile = config.sops.secrets."wireguard-domain".path;
    endpointFile = config.sops.secrets."wireguard-endpoint".path;
  };

  sops.age.keyFile = "/home/lukasf/.config/sops/age/keys.txt";

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
  powerManagement.powertop.enable = true;

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

  # Cap journald usage to reduce eMMC writes on low-capacity storage
  services.journald.extraConfig = ''
    SystemMaxUse=100M
    RuntimeMaxUse=50M
    RuntimeKeepFree=100M
    SystemMaxFileSize=10M
  '';

  services.resolved = {
    enable = true;
    dnssec = "false";
    fallbackDns = [ "1.1.1.1" "9.9.9.9" ];
  };
  networking.networkmanager.dns = "systemd-resolved";
  networking.resolvconf.enable = lib.mkForce false;
}
