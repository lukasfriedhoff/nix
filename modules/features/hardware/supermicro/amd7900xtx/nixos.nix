{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardwareProfiles.supermicro.amd7900Xtx;
in
{
  options.hardwareProfiles.supermicro.amd7900Xtx = {
    enable = lib.mkEnableOption "Supermicro AMD 7900 XTX GPU/host profile";
  };

  config = lib.mkIf cfg.enable {
    boot.initrd.availableKernelModules = [
      "ahci"
      "nvme"
      "xhci_pci"
      "usbhid"
      "sd_mod"
    ];
    boot.kernelModules = [
      "kvm-amd"
      "ipmi_si"
      "ipmi_devintf"
    ];
    boot.kernelParams = [
      "amdgpu.ppfeaturemask=0xffffffff"
      "pcie_aspm=off"
    ];
    boot.blacklistedKernelModules = lib.mkAfter [ "radeon" ];

    hardware = {
      cpu.amd.updateMicrocode = lib.mkDefault true;
      enableAllFirmware = true;
      graphics = {
        enable = true;
        extraPackages = with pkgs; [
          rocmPackages_6.rocm-smi
          mesa
        ];
      };
    };

    services.xserver.videoDrivers = [ "amdgpu" ];
    environment.systemPackages = with pkgs; [
      radeontop
      lm_sensors
      nvme-cli
      rocmPackages_6.rocm-smi
    ];

    networking.hostId = "feedface"; # replace with `head -c8 /etc/machine-id`

    powerManagement.cpuFreqGovernor = lib.mkDefault "performance";
  };
}
