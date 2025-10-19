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
    hostName = "lf-timebutler-testvm-01"; # Define your hostname.
    firewall.enable = false;
    # set static ip
    interfaces.ens18.ipv4.addresses = [ {
      address = "10.7.5.4";
      prefixLength = 24;
    }];
    defaultGateway = "10.7.5.254";
    nameservers = [ "1.1.1.1" ];
  };

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # enable k3s
  services.k3s.enable = true;
  services.k3s.role = "server";
  services.k3s.extraFlags = toString [
    # "--debug" # Optionally add additional args to k3s
  ];

  security.sudo.wheelNeedsPassword = false;

  services = {
    openssh = {
      enable = true;
      settings.PermitRootLogin = "yes"; 
      settings.PasswordAuthentication = true;
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
      hashedPassword = "$6$T2.TlxY598BdXCnK$uZo8sfvJlAn2jFrHKRQvmUsCvE0oU5F3I/PLDFKjsHfHlZ7K5aOSC8X4XJZFUxvs9QmDVOrFRGG8CvPYrXHVr1";
      # change this to your ssh key
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIChSy16zCpiQzAoXxX36keLgwO/+5L3o/MzvoLnRQjjP lukasfriedhoff@Lukass-MacBook-Pro.local"
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
      hashedPassword = "$6$Lzd17TPthOq2jH.Q$BCsqfAdbtvTpR02/1TazE9p/MT9u5jmdXj2pZ/UmeeaorVvTc6cOaJeAdzagp4.XKymcjsQrNXbCQ2jgPJOfa/";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIChSy16zCpiQzAoXxX36keLgwO/+5L3o/MzvoLnRQjjP lukasfriedhoff@Lukass-MacBook-Pro.local"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOBHeOqBSonGdmrJSD2lDZ01SAewq2bp7GYWPpStx2oJ root@8c96b522dff2"
      ];
    };

  };

  system.stateVersion = "25.05";
}