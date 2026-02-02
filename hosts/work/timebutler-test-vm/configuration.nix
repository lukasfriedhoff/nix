{
  modulesPath,
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disko.nix
  ];

  boot.loader.grub = {
    # no need to set devices, disko will add all devices that have a EF02 partition to the list already
    devices = [ ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  networking = {
    hostName = "lf-timebutler-testvm-01"; # Define your hostname.
    # set static ip
    interfaces.ens18.ipv4.addresses = [
      {
        address = "10.7.5.4";
        prefixLength = 24;
      }
    ];
    defaultGateway = "10.7.5.254";
    nameservers = [ "1.1.1.1" ];
  };

  # enable k3s
  services.k3s.enable = true;
  services.k3s.role = "server";
  services.k3s.extraFlags = toString [
    # "--debug" # Optionally add additional args to k3s
  ];

  dacoso.server = {
    # Pull hashed passwords / authorized keys from secrets/profiles/work/servers/timebutler-test-vm/.
    passwordFiles = {
      root = "root-password.hash";
      nixos = "nixos-password.hash";
    };
    sshKeyFiles = {
      root = [ "root.authorized_keys" ];
      nixos = [ "nixos.authorized_keys" ];
    };
    githubAccounts = [ "lukasfriedhoff" ];
    githubRefreshInterval = "daily";
    # authorizedKeysRepo = {
    #   url = "https://github.com/your-org/ssh-keys.git";
    #   rev = "<commit>";
    #   sha256 = "<nix-hash>";
    #   files = [ "authorized_keys" ];
    # };
  };
}
