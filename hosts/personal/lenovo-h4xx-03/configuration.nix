{
  config,
  inputs,
  lib,
  secrets,
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

  sops.secrets."login-password-hash" = {
    sopsFile = "${secrets.profileShared}/login-password-hash.txt";
    format = "binary";
    neededForUsers = true;
  };

  users.users.lukasf.hashedPasswordFile = config.sops.secrets."login-password-hash".path;
}
