{
  config,
  inputs,
  lib,
  pkgs,
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

  networking.hostName = "nuc-h4xx-04";

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

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 10;

  desktop.personalWorkstation = {
    enable = true;
    wireguardAddress = "10.1.90.7/24";
  };

  # Start the homelab WireGuard tunnel from the user session, as on
  # tux-h4xx-01 and lenovo-h4xx-03.
  lukasf.wireguard.homelab.userUnit.enable = true;

  # Intel Iris Plus 655 (i5-8259U) - integrated only, no discrete GPU.
  desktop.gaming.defaultRenderer = lib.mkDefault "intel";

  # Carried over from the srv2 era and still hardware-specific: this NUC's
  # Realtek NIC hangs with "NETDEV WATCHDOG: transmit queue 0 timed out" and
  # never recovers (kernel bugzilla 107421, RH 1733837/1692075). ASPM, EEE
  # and large offloads are the documented triggers. It caused the 2026-08-24
  # outage; the role change does not make the erratum go away.
  boot.kernelParams = [ "pcie_aspm=off" ];
  systemd.services.r8169-nic-quirks = {
    description = "Disable EEE and offloads on the Realtek NIC";
    wantedBy = [ "multi-user.target" ];
    after = [ "sys-subsystem-net-devices-enp1s0.device" ];
    bindsTo = [ "sys-subsystem-net-devices-enp1s0.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.ethtool}/bin/ethtool --set-eee enp1s0 eee off || true
      ${pkgs.ethtool}/bin/ethtool -K enp1s0 tso off gso off gro off || true
    '';
  };

  sops.secrets."login-password-hash" = {
    sopsFile = "${secrets.profileShared}/login-password-hash.txt";
    format = "binary";
    neededForUsers = true;
  };

  users.users.lukasf.hashedPasswordFile = config.sops.secrets."login-password-hash".path;
}
