{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  nets = import ../../../resources/homelab/networks.nix;
  lukasfPasswordHash = "$6$yzoypuzQDaJPoH3Q$jMjF9ciENiSRMMDfkeJJdGb9jMK1W35kNLvO3gH4B58rhWj285gYBI6n8.i8ry8jG5f7Ll3VxNbdvX5Sp2aGs0";
in

{
  imports = [
    inputs.disko.nixosModules.disko
    ../../common/default.nix
    ../common.nix
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = "srv2";
  boot.swraid.mdadmConf = "PROGRAM ${pkgs.coreutils}/bin/true";
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  networking.defaultGateway = lib.mkForce null;
  networking.nameservers = [ "10.1.30.1" ];
  networking.interfaces.enp1s0.useDHCP = lib.mkForce false;
  networking.vlans = {
    "enp1s0.20" = {
      inherit (nets.vlans.server) id;
      interface = "enp1s0";
    };
    "enp1s0.40" = {
      inherit (nets.vlans.storage) id;
      interface = "enp1s0";
    };
    "enp1s0.10" = {
      inherit (nets.vlans.lan) id;
      interface = "enp1s0";
    };
    "enp1s0.12" = {
      inherit (nets.vlans.iot) id;
      interface = "enp1s0";
    };
    "enp1s0.13" = {
      inherit (nets.vlans.windows) id;
      interface = "enp1s0";
    };
    "enp1s0.50" = {
      inherit (nets.vlans.lab) id;
      interface = "enp1s0";
    };
  };

  # Bring VLAN subinterfaces up even without an IP so bridges attach cleanly.
  networking.interfaces."enp1s0.20".useDHCP = false;
  networking.interfaces."enp1s0.40".useDHCP = false;
  networking.interfaces."enp1s0.10".useDHCP = false;
  networking.interfaces."enp1s0.12".useDHCP = false;
  networking.interfaces."enp1s0.13".useDHCP = false;
  networking.interfaces."enp1s0.50".useDHCP = false;

  # Libvirt-friendly bridges for each VLAN (mgmt on brvlan30).
  networking.bridges = {
    brvlan10.interfaces = [ "enp1s0.10" ];
    brvlan12.interfaces = [ "enp1s0.12" ];
    brvlan13.interfaces = [ "enp1s0.13" ];
    brvlan20.interfaces = [ "enp1s0.20" ];
    brvlan30.interfaces = [ "enp1s0" ]; # untagged mgmt
    brvlan40.interfaces = [ "enp1s0.40" ];
    brvlan50.interfaces = [ "enp1s0.50" ];
  };
  networking.interfaces.brvlan30 = {
    useDHCP = true;
    macAddress = "68:1d:ef:39:95:b2";
  };
  networking.interfaces.brvlan20.useDHCP = true;
  networking.interfaces.brvlan40.useDHCP = true;
  networking.hosts = {
    "127.0.0.2" = lib.mkForce [ ];
  };

  # Use MAC-based DHCP client ID on the management bridge.
  systemd.network.networks."30-brvlan30" = {
    matchConfig.Name = "brvlan30";
    networkConfig.DHCP = "yes";
    dhcpV4Config.ClientIdentifier = "mac";
  };

  homelab.personalServer = {
    enable = true;
    managementPubKey = null;
    usePasswordAuth = false;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.initrdSsh = {
    enable = true;
    authorizedKeyFile = ./initrd-authorized.pub;
  };

  boot.initrd.network.udhcpc.enable = true;
  boot.initrd.network.udhcpc.extraArgs = [
    # Some switches delay forwarding briefly after link-up (STP/listen state).
    # Retry longer so initrd SSH unlock remains available during boot.
    "-t"
    "20"
    "-T"
    "3"
    "-x"
    # DHCP option 61 (client identifier): 01 + MAC (no separators)
    "0x3d:01681def3995b2"
    "-x"
    "hostname:srv2"
  ];

  boot.initrd.availableKernelModules = lib.mkAfter [
    "e1000e"
    "igb"
    "igc"
    "ixgbe"
    "r8169"
    "r8152"
  ];

  networking.extraHosts = ''
    # srv2 srv2.lab.h4xx.io 10.42.1.91
  '';

  users.groups.sudo = { };

  users.users.lukasf = {
    isNormalUser = true;
    group = "users";
    extraGroups = [
      "sudo"
      "wheel"
    ];
    hashedPassword = lukasfPasswordHash;
  };

  users.users.root = {
    initialHashedPassword = lib.mkForce null;
    hashedPassword = lukasfPasswordHash;
  };
}
