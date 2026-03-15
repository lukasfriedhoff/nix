{
  inputs,
  ...
}:

{
  imports = [
    inputs.disko.nixosModules.disko
    ../../common/default.nix
    ../common.nix
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = "srv3";
  shared.network.domain = "lab.h4xx.io";

  homelab.personalServer = {
    enable = true;
    # Keep bootstrap SSH key from initrd-authorized.pub; avoid blocking install on this secret.
    managementPubKey = null;
    usePasswordAuth = false;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200n8"
    "console=ttyS1,115200n8"
  ];

  homelab.initrdSsh = {
    enable = true;
    authorizedKeyFile = ./initrd-authorized.pub;
  };

  boot.initrd.network.udhcpc.enable = true;
  boot.initrd.network.udhcpc.extraArgs = [
    "-t"
    "10"
    "-x"
    # DHCP option 61 (client identifier): 01 + mgmt MAC (52:54:00:0a:dd:ea)
    "0x3d:015254000addea"
    "-x"
    "hostname:srv3"
  ];

  networking.extraHosts = ''
    # srv3 srv3.lab.h4xx.io
  '';
}
