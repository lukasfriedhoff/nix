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
    managementPubKey = "ssh/srv3-personal-mgmt.pub";
    usePasswordAuth = false;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.initrdSsh = {
    enable = true;
    authorizedKeyFile = ./initrd-authorized.pub;
  };

  networking.extraHosts = ''
    # srv3 srv3.lab.h4xx.io
  '';
}
