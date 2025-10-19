{ modulesPath, config, lib, pkgs, ... }: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
  ];

  # allow unfree packages to be installed
  nixpkgs.config = {
    allowUnfree = true;
  };

  boot.loader.grub = {
    # no need to set devices, disko will add all devices that have a EF02 partition to the list already
    # devices = [ ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking = {
    hostName = "docker-host-01"; # Define your hostname.
    firewall.enable = false;
    # set static ip
    interfaces.ens18.ipv4.addresses = [ {
      address = "10.7.5.5";
      prefixLength = 24;
    }];
    defaultGateway = "10.7.5.254";
    nameservers = [ "1.1.1.1" ];
  };

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # enable docker
  virtualisation.docker.enable = true;

  security.sudo.wheelNeedsPassword = false;

  services = {
    openssh = {
      enable = true;
      settings.PermitRootLogin = "yes"; 
      settings.PasswordAuthentication = true;
    };

    cron = {
      enable = true;
      systemCronJobs = [
        # hourly backup of netbox
        "0 * * * * root . /home/nixos/.envrc && restic backup /home/nixos/docker/netbox --host $HOSTNAME --tag $HOSTNAME --verbose && restic forget --host $HOSTNAME --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune >> /tmp/cron.log"
      ];
    };
    # enable a prometheus node exporter
    prometheus.exporters.node.enable = true;
    
  };

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal

    # UNCOMMENT the following to install these packages systemwide
    pkgs.bash
    pkgs.vim
    pkgs.tmux
    pkgs.wget
    pkgs.htop
    pkgs.jq
    pkgs.restic
    pkgs.direnv
    pkgs.python3
    pkgs.python3Packages.pip
  ];

  # make users immutable
  users.mutableUsers = false;

  # enable direnv globally
  programs.direnv.enable = true;

  users.users = {

    root = {
      # set a password for root user
      # generate password hash: nix shell nixpkgs#mkpasswd -c mkpasswd -
      hashedPassword = "$6$rsL/kjpK78sSuLzL$Mvm8SBZDssS4jXHzPfTcfQJSGrGA607590098IqsT6qCHVd0dRAAfyDwIpLsjO09n3cYhwYsIxxIYir53NyAl/";
      # change this to your ssh key
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIChSy16zCpiQzAoXxX36keLgwO/+5L3o/MzvoLnRQjjP lukasfriedhoff@Lukass-MacBook-Pro.local"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOBHeOqBSonGdmrJSD2lDZ01SAewq2bp7GYWPpStx2oJ root@8c96b522dff2"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB5CWwrN8qt9GcGeh+utY2bbB6SM7RGm0I1p91KthNh/ frank.bartnitzek@dacoso.com"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFBjbldWwEitDpgR4bYe3Fg/R5hPOUgbfQ0rGcY9enKR carsten.rilitz@dacoso.com"
      ];
    };

    # enable the nixos user
    nixos = {
      isNormalUser = true; 
      shell = pkgs.bash; 
      description = "nixos user"; 
      extraGroups = [ 
        "networkmanager" 
        "wheel" 
        "docker"
      ]; 
      # generate password hash: nix shell nixpkgs#mkpasswd -c mkpasswd -m sha-512
      hashedPassword = "$6$rsL/kjpK78sSuLzL$Mvm8SBZDssS4jXHzPfTcfQJSGrGA607590098IqsT6qCHVd0dRAAfyDwIpLsjO09n3cYhwYsIxxIYir53NyAl/";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIChSy16zCpiQzAoXxX36keLgwO/+5L3o/MzvoLnRQjjP lukasfriedhoff@Lukass-MacBook-Pro.local"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOBHeOqBSonGdmrJSD2lDZ01SAewq2bp7GYWPpStx2oJ root@8c96b522dff2"
      ];
    };

  };

  system.stateVersion = "25.05";
}