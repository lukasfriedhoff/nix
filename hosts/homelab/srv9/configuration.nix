{
  config,
  secrets,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  hostName = "srv9";
  clusterDomain = "lab.h4xx.io";
  prodApiHost = "srv2.lab.h4xx.io";
  managementInterface = "eno1np0";
  managementMac = "e4:43:4b:f2:1a:42";
  systemDiskId = "scsi-35002538b11337b60";
  k3sTokenSecret = "${secrets.primary}/k3s-server-token.txt";
  loginPasswordHashSecret = "${secrets.primary}/login-password-hash.txt";
  hasK3sToken = builtins.pathExists k3sTokenSecret;
  nets = import ../../../resources/homelab/networks.nix;
  longhornDisks = lib.filterAttrs (_: disk: disk.host == hostName && disk.purpose == "longhorn") (
    import ../../../resources/homelab/disks.nix
  );
  longhornDiskIds = builtins.attrNames longhornDisks;
  longhornDiskIndex = lib.listToAttrs (
    lib.imap0 (index: diskId: {
      name = diskId;
      value = index + 1;
    }) longhornDiskIds
  );
in
{
  imports = [
    inputs.disko.nixosModules.disko
    ../../common/default.nix
    ../common.nix
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking = {
    inherit hostName;
    useNetworkd = true;
    networkmanager.enable = false;
    defaultGateway = lib.mkForce null;
    nameservers = [ "10.1.30.1" ];

    interfaces = {
      "${managementInterface}".useDHCP = lib.mkForce false;
      "${managementInterface}.10".useDHCP = false;
      "${managementInterface}.12".useDHCP = false;
      "${managementInterface}.13".useDHCP = false;
      "${managementInterface}.20".useDHCP = false;
      "${managementInterface}.40".useDHCP = false;
      "${managementInterface}.50".useDHCP = false;
      brvlan20.useDHCP = true;
      brvlan30 = {
        useDHCP = true;
        macAddress = managementMac;
      };
      brvlan40.useDHCP = true;
    };

    vlans = {
      "${managementInterface}.10" = {
        inherit (nets.vlans.lan) id;
        interface = managementInterface;
      };
      "${managementInterface}.12" = {
        inherit (nets.vlans.iot) id;
        interface = managementInterface;
      };
      "${managementInterface}.13" = {
        inherit (nets.vlans.windows) id;
        interface = managementInterface;
      };
      "${managementInterface}.20" = {
        inherit (nets.vlans.server) id;
        interface = managementInterface;
      };
      "${managementInterface}.40" = {
        inherit (nets.vlans.storage) id;
        interface = managementInterface;
      };
      "${managementInterface}.50" = {
        inherit (nets.vlans.lab) id;
        interface = managementInterface;
      };
    };

    bridges = {
      brvlan10.interfaces = [ "${managementInterface}.10" ];
      brvlan12.interfaces = [ "${managementInterface}.12" ];
      brvlan13.interfaces = [ "${managementInterface}.13" ];
      brvlan20.interfaces = [ "${managementInterface}.20" ];
      brvlan30.interfaces = [ managementInterface ];
      brvlan40.interfaces = [ "${managementInterface}.40" ];
      brvlan50.interfaces = [ "${managementInterface}.50" ];
    };

    hosts."127.0.0.2" = lib.mkForce [ ];
  };

  shared.network.domain = clusterDomain;

  systemd.network = {
    netdevs."40-brvlan30".netdevConfig = {
      Name = "brvlan30";
      Kind = "bridge";
      MACAddress = managementMac;
    };
    networks = {
      "30-brvlan30" = {
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
      "20-brvlan20" = {
        matchConfig.Name = "brvlan20";
        networkConfig.DHCP = "yes";
        dhcpV4Config.RouteMetric = 200;
      };
      "40-brvlan40" = {
        matchConfig.Name = "brvlan40";
        networkConfig.DHCP = "yes";
        dhcpV4Config.RouteMetric = 300;
      };
    };
  };

  homelab.personalServer = {
    enable = true;
    managementPubKey = null;
    usePasswordAuth = false;
  };

  users.users = {
    root = {
      initialHashedPassword = lib.mkForce null;
      hashedPasswordFile = config.sops.secrets."srv9-login-password-hash".path;
      openssh.authorizedKeys.keyFiles = [ ./initrd-authorized.pub ];
    };
    nixos.openssh.authorizedKeys.keyFiles = [ ./initrd-authorized.pub ];
    lukasf = {
      isNormalUser = true;
      group = "users";
      extraGroups = [
        "sudo"
        "wheel"
      ];
      hashedPasswordFile = config.sops.secrets."srv9-login-password-hash".path;
    };
  };
  users.groups.sudo = { };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd = {
      availableKernelModules = lib.mkAfter [
        "i40e"
        "igb"
        "megaraid_sas"
      ];
      kernelModules = [
        "i40e"
        "megaraid_sas"
      ];
      network.udhcpc = {
        enable = true;
        extraArgs = [
          "-i"
          managementInterface
          "-t"
          "20"
          "-T"
          "3"
          "-x"
          "0x3d:01e4434bf21a42"
          "-x"
          "hostname:srv9"
        ];
      };
      luks.devices = lib.mkForce {
        cryptroot = {
          device = "/dev/disk/by-id/${systemDiskId}-part2";
          allowDiscards = true;
        };
      };
    };
  };

  homelab.initrdSsh = {
    enable = true;
    authorizedKeyFile = ./initrd-authorized.pub;
  };

  sops.secrets = {
    "srv9-login-password-hash" = {
      sopsFile = loginPasswordHashSecret;
      format = "binary";
      neededForUsers = true;
    };
    "srv9-longhorn-luks-key" = {
      sopsFile = "${secrets.profileShared}/luks/srv9-longhorn.txt";
      format = "binary";
      mode = "0400";
      owner = "root";
    };
    "k3s-server-token" = lib.mkIf hasK3sToken {
      sopsFile = k3sTokenSecret;
      format = "binary";
      mode = "0400";
      owner = "root";
    };
  };

  systemd.services.srv9-longhorn-disks = {
    description = "Unlock and mount srv9 Longhorn data disks";
    # sops-nix installs secrets from the setupSecrets activation script, not a
    # systemd unit, so there is no sops-install-secrets.service to order on.
    # Requiring a unit that does not exist makes switch-to-configuration abort.
    after = [ "systemd-udev-settle.service" ];
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

      unlockMount() {
        local device="$1"
        local mapper="$2"
        local mountpoint="$3"
        local mapperStatus

        mkdir -p "$mountpoint"

        # `cryptsetup status` prints "<mapper> is inactive." for a mapping that
        # does not exist, so a non-empty value here does NOT mean the device is
        # open. Treating it as "already unlocked" skips the unlock below and
        # then trips `test -b /dev/mapper/$mapper` on every cold boot, which is
        # what left this host with k3s down and its Longhorn disks unmounted.
        mapperStatus="$(cryptsetup status "$mapper" 2>/dev/null || true)"
        case "$mapperStatus" in
          *"is inactive"*)
            mapperStatus=""
            ;;
          *"device: (null)"*)
            if findmnt -rn "$mountpoint" >/dev/null 2>&1; then
              umount "$mountpoint" || true
            fi
            cryptsetup close "$mapper" || true
            mapperStatus=""
            ;;
        esac

        if [ -z "$mapperStatus" ]; then
          test -b "$device"
          test -r ${config.sops.secrets."srv9-longhorn-luks-key".path}
          ${pkgs.coreutils}/bin/tr -d '\r\n' \
            < ${config.sops.secrets."srv9-longhorn-luks-key".path} \
            | cryptsetup open "$device" "$mapper" --key-file=-
        fi

        test -b "/dev/mapper/$mapper"

        if findmnt -rn "$mountpoint" >/dev/null 2>&1; then
          if ! (printf ok > "$mountpoint/.longhorn-mount-check") 2>/dev/null; then
            umount "$mountpoint" || true
          else
            rm -f "$mountpoint/.longhorn-mount-check"
          fi
        fi

        if ! findmnt -rn "$mountpoint" >/dev/null 2>&1; then
          mount "/dev/mapper/$mapper" "$mountpoint"
        fi

        printf ok > "$mountpoint/.longhorn-mount-check"
        rm -f "$mountpoint/.longhorn-mount-check"
        chmod 0755 "$mountpoint"
      }

      ${lib.concatStringsSep "\n" (
        map (diskId: ''
          unlockMount /dev/disk/by-id/${diskId}-part1 cryptlonghorn${
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

  services.k3s = lib.mkIf hasK3sToken {
    role = lib.mkForce "agent";
    serverAddr = "https://${prodApiHost}:6443";
    tokenFile = config.sops.secrets."k3s-server-token".path;
    extraFlags = lib.mkForce [
      "--node-name=${hostName}"
      "--node-ip=10.1.30.31"
      "--kubelet-arg=max-pods=250"
    ];
  };

  systemd.services.k3s = lib.mkIf hasK3sToken {
    after = [ "srv9-longhorn-disks.service" ];
    requires = [ "srv9-longhorn-disks.service" ];
  };
}
