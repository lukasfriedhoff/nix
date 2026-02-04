{
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ../../common/default.nix
    ./disko.nix
  ];

  boot.loader.grub = {
    # no need to set devices, disko will add all devices that have a EF02 partition to the list already
    devices = [ ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  networking = {
    hostName = "docker-host-01"; # Define your hostname.
    # set static ip
    interfaces.ens18.ipv4.addresses = [
      {
        address = "10.7.5.5";
        prefixLength = 24;
      }
    ];
    defaultGateway = "10.7.5.254";
    nameservers = [ "1.1.1.1" ];
  };

  # enable docker
  virtualisation.docker.enable = true;

  services.cron = {
    enable = true;
    systemCronJobs = [
      # hourly backup of netbox
      "0 * * * * root . /home/nixos/.envrc && restic backup /home/nixos/docker/netbox --host $HOSTNAME --tag $HOSTNAME --verbose && restic forget --host $HOSTNAME --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune >> /tmp/cron.log"
    ];
  };

  dacoso.server = {
    # Password/key material lives under secrets/profiles/work/servers/docker-host-01/ to keep work credentials separate.
    passwordFiles = {
      root = "root-password.hash";
      nixos = "nixos-password.hash";
    };
    sshKeyFiles = {
      root = [ "root.authorized_keys" ];
      nixos = [ "nixos.authorized_keys" ];
    };
    extraSystemPackages = with pkgs; [ restic ];
    githubAccounts = [ "lukasfriedhoff" ];
    githubRefreshInterval = "daily";
    # Uncomment and fill in to pull additional keys from a shared repository:
    # authorizedKeysRepo = {
    #   url = "https://github.com/your-org/ssh-keys.git";
    #   rev = "<commit>";
    #   sha256 = "<nix-hash>";
    #   files = [ "authorized_keys" ];
    # };
  };
}
