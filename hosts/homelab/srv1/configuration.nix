{
  config,
  inputs,
  lib,
  secrets,
  ...
}:

let
  homelabDisks = import ../../../resources/homelab/disks.nix;
  cephDiskEntries = lib.filterAttrs (_: v: v.host == "srv1" && v.purpose == "ceph") homelabDisks;
  cephDisks = map (diskId: "/dev/disk/by-id/${diskId}") (lib.attrNames cephDiskEntries);
in
{
  imports = [
    inputs.disko.nixosModules.disko
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = "srv1";
  networking.domain = "lab.h4xx.io";

  homelab.personalServer = {
    enable = true;
    managementPubKey = "ssh/srv1-personal-mgmt.pub";
    usePasswordAuth = false;
  };

  lukasf.nixCache = {
    enable = true;
    secretKeyFile = "nix-cache/nix-serve.key";
    publicKey = builtins.readFile ../../../resources/nix-cache/personal-cache.pub;
    openFirewall = true;
    configureClient = true;
  };

  lukasf.serverDeployment.enableComin = true;

  lukasf.seaweedfs.enable = false;

  lukasf.ceph = {
    enable = true;
    bootstrap = {
      monIp = "10.1.30.5";
      singleHostDefaults = true;
      skipDashboard = true;
    };
    osd = {
      devices = cephDisks;
      encrypted = true;
      autoProvision = true;
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  sops.age.keyFile = "/var/lib/sops-nix/age/keys.txt";

  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;
      authorizedKeys = [ (builtins.readFile ./initrd-authorized.pub) ];
      hostKeys = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [ (builtins.readFile ./initrd-authorized.pub) ];
  users.users.nixos.openssh.authorizedKeys.keys = [ (builtins.readFile ./initrd-authorized.pub) ];

  networking.firewall.allowedTCPPorts = [ 4243 ];

  networking.extraHosts = ''
    # srv1 srv1.lab.h4xx.io 10.1.30.12
  '';
}
