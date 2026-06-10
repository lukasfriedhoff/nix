{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  hostName = "srv8";
  clusterDomain = "lab.h4xx.io";
  prodApiHost = "srv2.lab.h4xx.io";
  mgmtMac = "1c:83:41:33:1b:37";
  k3sTokenSecret = ../../../secrets/profiles/personal/servers/srv8/k3s-server-token.txt;
  hasK3sToken = builtins.pathExists k3sTokenSecret;
  nets = import ../../../resources/homelab/networks.nix;
  longhornDisks = lib.filterAttrs (_: v: v.host == hostName && v.purpose == "longhorn") (
    import ../../../resources/homelab/disks.nix
  );
  longhornDiskIds = builtins.attrNames longhornDisks;
  longhornDiskIndex = lib.listToAttrs (
    lib.imap0 (idx: diskId: {
      name = diskId;
      value = idx + 1;
    }) longhornDiskIds
  );
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

  networking.hostName = hostName;
  shared.network.domain = clusterDomain;
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  networking.defaultGateway = lib.mkForce null;
  networking.nameservers = [ "10.1.30.1" ];

  networking.interfaces.enp4s0.useDHCP = lib.mkForce false;
  networking.interfaces.eno1.useDHCP = lib.mkForce false;
  networking.bonds.bond0 = {
    interfaces = [
      "enp4s0"
      "eno1"
    ];
    driverOptions = {
      mode = "active-backup";
      primary = "enp4s0";
      miimon = "100";
    };
  };
  systemd.network.netdevs."40-bond0".netdevConfig = {
    Name = "bond0";
    Kind = "bond";
    MACAddress = mgmtMac;
  };

  networking.vlans = {
    "bond0.20" = {
      inherit (nets.vlans.server) id;
      interface = "bond0";
    };
    "bond0.40" = {
      inherit (nets.vlans.storage) id;
      interface = "bond0";
    };
    "bond0.10" = {
      inherit (nets.vlans.lan) id;
      interface = "bond0";
    };
    "bond0.12" = {
      inherit (nets.vlans.iot) id;
      interface = "bond0";
    };
    "bond0.13" = {
      inherit (nets.vlans.windows) id;
      interface = "bond0";
    };
    "bond0.50" = {
      inherit (nets.vlans.lab) id;
      interface = "bond0";
    };
  };

  networking.interfaces."bond0.20".useDHCP = false;
  networking.interfaces."bond0.40".useDHCP = false;
  networking.interfaces."bond0.10".useDHCP = false;
  networking.interfaces."bond0.12".useDHCP = false;
  networking.interfaces."bond0.13".useDHCP = false;
  networking.interfaces."bond0.50".useDHCP = false;

  networking.bridges = {
    brvlan10.interfaces = [ "bond0.10" ];
    brvlan12.interfaces = [ "bond0.12" ];
    brvlan13.interfaces = [ "bond0.13" ];
    brvlan20.interfaces = [ "bond0.20" ];
    brvlan30.interfaces = [ "bond0" ];
    brvlan40.interfaces = [ "bond0.40" ];
    brvlan50.interfaces = [ "bond0.50" ];
  };

  networking.interfaces.brvlan30 = {
    useDHCP = true;
    macAddress = mgmtMac;
  };
  systemd.network.netdevs."40-brvlan30".netdevConfig = {
    Name = "brvlan30";
    Kind = "bridge";
    MACAddress = mgmtMac;
  };
  networking.interfaces.brvlan20.useDHCP = true;
  networking.interfaces.brvlan40.useDHCP = true;
  networking.hosts."127.0.0.2" = lib.mkForce [ ];
  networking.extraHosts = ''
    10.1.30.26 srv2 srv2.lab.h4xx.io
    10.1.30.27 srv8 srv8.lab.h4xx.io
  '';

  systemd.network.networks."30-brvlan30" = {
    matchConfig.Name = "brvlan30";
    networkConfig.DHCP = "yes";
    dhcpV4Config = {
      ClientIdentifier = "mac";
      RouteMetric = 100;
    };
    routes = [
      {
        Destination = "0.0.0.0/0";
        Gateway = "10.1.30.1";
        Metric = 100;
      }
      {
        Destination = "10.1.90.0/24";
        Gateway = "10.1.30.1";
      }
    ];
  };
  systemd.network.networks."20-brvlan20" = {
    matchConfig.Name = "brvlan20";
    networkConfig.DHCP = "yes";
    dhcpV4Config.RouteMetric = 200;
  };
  systemd.network.networks."40-brvlan40" = {
    matchConfig.Name = "brvlan40";
    networkConfig.DHCP = "yes";
    dhcpV4Config.RouteMetric = 300;
  };

  homelab.personalServer = {
    enable = true;
    managementPubKey = null;
    usePasswordAuth = false;
  };

  users.users.root.openssh.authorizedKeys.keyFiles = [ ./initrd-authorized.pub ];
  users.users.nixos.openssh.authorizedKeys.keyFiles = [ ./initrd-authorized.pub ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.initrdSsh = {
    enable = true;
    authorizedKeyFile = ./initrd-authorized.pub;
  };

  boot.initrd.network.udhcpc.enable = true;
  # Pin udhcpc to enp4s0 (igc, mgmt MAC 1c:83:41:33:1b:37). The wrapper script
  # in nixpkgs initrd-network.nix runs `udhcpc -i $iface … ${udhcpcArgs}` and
  # iterates over every NIC found in /sys/class/net; a trailing `-i enp4s0`
  # overrides the loop variable so DHCP always goes out the cabled port instead
  # of eno1 (r8169) which currently has no carrier.
  boot.initrd.network.udhcpc.extraArgs = [
    "-i"
    "enp4s0"
    "-t"
    "20"
    "-T"
    "3"
    "-x"
    "0x3d:011c8341331b37"
    "-x"
    "hostname:srv8"
  ];
  boot.initrd.availableKernelModules = lib.mkAfter [
    "igc"
    "r8169"
    "r8152"
  ];
  # Force-load the Intel 2.5G driver early so enp4s0 is in /sys/class/net by
  # the time the DHCP loop runs (availableKernelModules waits for a udev
  # device-trigger match, which has been racing the network setup).
  boot.initrd.kernelModules = [ "igc" ];

  # Only cryptroot is unlocked in initrd. Disko registers every LUKS content
  # type in boot.initrd.luks.devices unconditionally, which makes stage 1
  # prompt for three longhorn passphrases before the root prompt. Those are
  # unlocked in stage 2 by srv8-longhorn-disks.service.
  boot.initrd.luks.devices = lib.mkForce {
    cryptroot = {
      device = "/dev/disk/by-partlabel/disk-main-root";
      allowDiscards = true;
    };
  };

  sops.secrets."srv8-longhorn-luks-key" = {
    sopsFile = ../../../secrets/profiles/personal/shared/luks/srv8-longhorn.txt;
    format = "binary";
    mode = "0400";
    owner = "root";
  };

  systemd.services.srv8-longhorn-disks = {
    description = "Unlock and mount srv8 Longhorn data disks";
    after = [
      "sops-install-secrets.service"
      "systemd-udev-settle.service"
    ];
    before = lib.optionals hasK3sToken [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.coreutils
      pkgs.cryptsetup
      pkgs.util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      unlock_mount() {
        local device="$1"
        local mapper="$2"
        local mountpoint="$3"

        mkdir -p "$mountpoint"

        if ! cryptsetup status "$mapper" >/dev/null 2>&1; then
          # Strip CR/LF before feeding to cryptsetup so the on-disk passphrase
          # matches what deploy-from-iso.sh / new-host.sh wrote at install time
          # (both apply `tr -d '\r\n'` to the SOPS payload). Same pattern as
          # srv5-bootstrap-password.service.
          ${pkgs.coreutils}/bin/tr -d '\r\n' \
            < ${config.sops.secrets."srv8-longhorn-luks-key".path} \
            | cryptsetup open "$device" "$mapper" --key-file=-
        fi

        if ! findmnt -rn "$mountpoint" >/dev/null 2>&1; then
          mount "/dev/mapper/$mapper" "$mountpoint"
        fi

        chmod 0700 "$mountpoint"
      }

      ${lib.concatStringsSep "\n" (
        map (diskId: ''
          unlock_mount /dev/disk/by-id/${diskId}-part1 cryptlonghorn${
            toString longhornDiskIndex.${diskId}
          } /var/lib/longhorn-disk${toString longhornDiskIndex.${diskId}}
        '') longhornDiskIds
      )}
    '';
  };

  homelab.kubernetes = lib.mkIf hasK3sToken {
    enable = true;
    longhorn.enable = true;
  };

  sops.secrets."k3s-server-token" = lib.mkIf hasK3sToken {
    sopsFile = k3sTokenSecret;
    format = "binary";
    mode = "0400";
    owner = "root";
  };

  services.k3s = lib.mkIf hasK3sToken {
    role = lib.mkForce "agent";
    serverAddr = "https://${prodApiHost}:6443";
    tokenFile = config.sops.secrets."k3s-server-token".path;
    extraFlags = lib.mkForce [
      "--node-ip=10.1.30.27"
      "--kubelet-arg=max-pods=250"
    ];
  };

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
