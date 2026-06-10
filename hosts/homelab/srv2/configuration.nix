{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  nets = import ../../../resources/homelab/networks.nix;
  hostName = "srv2";
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
  systemd.network.netdevs."40-brvlan30".netdevConfig = {
    Name = "brvlan30";
    Kind = "bridge";
    MACAddress = "68:1d:ef:39:95:b2";
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

  # Keep server/storage VLAN addresses, but avoid competing default routes.
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

  sops.secrets."flux-cluster-token" = {
    sopsFile = ../../../secrets/profiles/personal/servers/srv2/flux-cluster-bootstrap-token.txt;
    owner = "root";
    format = "binary";
    mode = "0400";
  };

  sops.secrets."flux-sops-age-key" = {
    sopsFile = ../../../secrets/profiles/personal/servers/srv2/flux-sops-age.key;
    format = "binary";
    mode = "0400";
    owner = "root";
  };

  sops.secrets."srv2-longhorn-luks-key" = {
    sopsFile = ../../../secrets/profiles/personal/shared/luks/srv2-mdraid.txt;
    format = "binary";
    mode = "0400";
    owner = "root";
  };

  systemd.services.srv2-longhorn-disks = {
    description = "Unlock and mount srv2 Longhorn data disks";
    after = [
      "sops-install-secrets.service"
      "systemd-udev-settle.service"
    ];
    before = [ "k3s.service" ];
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
      unlock_mount() {
        local device="$1"
        local mapper="$2"
        local mountpoint="$3"

        mkdir -p "$mountpoint"

        if ! cryptsetup status "$mapper" >/dev/null 2>&1; then
          cryptsetup open "$device" "$mapper" \
            --key-file ${config.sops.secrets."srv2-longhorn-luks-key".path}
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

  homelab.kubernetes = {
    enable = true;
    longhorn.enable = true;
    extraK3sFlags = [
      "--tls-san srv2.lab.h4xx.io"
      "--tls-san srv2"
      "--tls-san 10.1.30.26"
      "--node-ip=10.1.30.26"
      "--kubelet-arg=max-pods=250"
    ];
    gitops = {
      enable = true;
      repoURL = "https://github.com/lukasfriedhoff/flux-cluster.git";
      branch = "develop";
      path = "./overlays/homelab";
      tokenFile = config.sops.secrets."flux-cluster-token".path;
      sopsAgeKeyFile = config.sops.secrets."flux-sops-age-key".path;
      username = "lukasfriedhoff";
      sourceName = "flux-cluster";
      kustomizationName = "homelab";
    };
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

  # Only cryptroot is unlocked in initrd. Disko registers every LUKS content
  # type in boot.initrd.luks.devices unconditionally, which makes stage 1
  # stall waiting for the longhorn data partitions. Those are unlocked in
  # stage 2 by srv2-longhorn-disks.service.
  boot.initrd.luks.devices = lib.mkForce {
    cryptroot = {
      device = "/dev/disk/by-partlabel/disk-main-root";
      allowDiscards = true;
    };
  };

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
