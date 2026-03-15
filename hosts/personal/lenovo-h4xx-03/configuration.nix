{
  inputs,
  lib,
  ...
}:

{
  imports = [
    ../../common/default.nix
    ./hardware-configuration.nix
    inputs.disko.nixosModules.disko
    ./disko.nix
  ];

  networking.hostName = "lenovo-h4xx-03";

  # Keep the system decryption key on the root filesystem so setupSecrets does
  # not depend on /home being mounted during early boot.
  sops.age.keyFile = "/var/lib/sops-nix/age/keys.txt";

  system.activationScripts.bootstrapSopsAgeKey = {
    text = ''
      if [ ! -s /var/lib/sops-nix/age/keys.txt ] && [ -s /home/lukasf/.config/sops/age/keys.txt ]; then
        install -d -m 0700 /var/lib/sops-nix/age
        install -m 0600 /home/lukasf/.config/sops/age/keys.txt /var/lib/sops-nix/age/keys.txt
      fi
    '';
  };

  hardwareProfiles.lenovo.thinkpadP15Gen2i.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 10;
  boot.loader.generic-extlinux-compatible.configurationLimit = lib.mkDefault 10;
  boot.loader.grub.configurationLimit = lib.mkDefault 10;
  boot.resumeDevice = "/dev/mapper/vg0-swap";

  desktop.personalWorkstation = {
    enable = true;
    wireguardAddress = "10.1.90.5/24";
    cephClientName = "lenovo";
  };

  # Match tux-h4xx-01 behavior: start homelab WireGuard from the user session.
  lukasf.wireguard.homelab.userUnit.enable = true;

  desktop.gaming.defaultRenderer = "nvidia";

  lukasf.kvm.enable = true;

  users.users.lukasf.extraGroups = lib.mkAfter [
    "input"
    "libvirtd"
    "kvm"
  ];

  boot.kernelModules = [ "uinput" ];
  services.udev.extraRules = ''
    KERNEL=="uinput", MODE="0660", GROUP="input"
  '';

  users.users.lukasf.hashedPassword = "$6$yzoypuzQDaJPoH3Q$jMjF9ciENiSRMMDfkeJJdGb9jMK1W35kNLvO3gH4B58rhWj285gYBI6n8.i8ry8jG5f7Ll3VxNbdvX5Sp2aGs0";
}
