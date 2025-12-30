{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.seaweedfs;
  inherit (lib)
    concatStringsSep
    mkEnableOption
    mkIf
    mkOption
    optional
    optionalAttrs
    optionalString
    types
    ;

  nodeCfg = cfg.cluster.nodes.${cfg.nodeName} or null;
  roles = if cfg.roles != [ ] then cfg.roles else (nodeCfg.roles or [ ]);
  hasRole = role: lib.elem role roles;

  nodeAddress =
    if cfg.nodeAddress != null then
      cfg.nodeAddress
    else if nodeCfg != null then
      nodeCfg.address
    else
      cfg.nodeName;

  masterNodes = lib.filterAttrs (_: node: lib.elem "master" node.roles) cfg.cluster.nodes;
  masterAddresses =
    if cfg.cluster.nodes != { } then
      lib.mapAttrsToList (_: node: "${node.address}:${toString cfg.cluster.masterPort}") masterNodes
    else if cfg.cluster.masterServers != [ ] then
      cfg.cluster.masterServers
    else if hasRole "master" then
      [ "${nodeAddress}:${toString cfg.cluster.masterPort}" ]
    else
      [ ];
  masterList = concatStringsSep "," masterAddresses;

  masterPeers = if lib.length masterAddresses > 1 then masterList else "";

  bootstrapMaster =
    cfg.cluster.bootstrapMaster
    || (cfg.cluster.autoBootstrap && hasRole "master" && lib.length masterAddresses == 1);

  diskEntries = map (
    disk:
    let
      diskId = builtins.baseNameOf disk;
      mountPoint = "${cfg.volume.mountBase}/${diskId}";
      partDevice = "${disk}-part1";
      mapperName = "${cfg.volume.encryption.namePrefix}-${diskId}";
      mapperDevice = "/dev/mapper/${mapperName}";
      keyFile = cfg.volume.encryption.keyFiles.${diskId} or null;
    in
    {
      inherit
        disk
        diskId
        mountPoint
        partDevice
        mapperName
        mapperDevice
        keyFile
        ;
    }
  ) cfg.volume.disks;

  volumeDataDirs =
    if cfg.volume.disks != [ ] then map (entry: entry.mountPoint) diskEntries else cfg.volume.dataDirs;

  weed = "${pkgs.seaweedfs}/bin/weed";
  volumeDirs = concatStringsSep "," volumeDataDirs;
in
{
  options.lukasf.seaweedfs = {
    enable = mkEnableOption "SeaweedFS services";

    nodeName = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Logical name for this node within the cluster.";
    };

    nodeAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "IP or hostname to advertise for this node. Defaults to the cluster entry or nodeName.";
    };

    bindAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Address to bind service listeners to.";
    };

    roles = mkOption {
      type = types.listOf (
        types.enum [
          "master"
          "volume"
          "filer"
        ]
      );
      default = [ ];
      description = "Roles enabled on this node. If empty, roles are derived from cluster.nodes.<nodeName>.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open the SeaweedFS service ports in the firewall.";
    };

    cluster = {
      nodes = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              address = mkOption {
                type = types.str;
                description = "Advertised address for the node.";
              };
              roles = mkOption {
                type = types.listOf (
                  types.enum [
                    "master"
                    "volume"
                    "filer"
                  ]
                );
                default = [ ];
                description = "Roles to run on this node.";
              };
            };
          }
        );
        default = { };
        description = "Cluster membership by nodeName. Use this to define 1..N nodes in one place.";
      };

      masterServers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Explicit master list (host:port). Ignored when cluster.nodes is set.";
      };

      masterPort = mkOption {
        type = types.ints.positive;
        default = 9333;
        description = "Master HTTP port.";
      };

      volumePort = mkOption {
        type = types.ints.positive;
        default = 8080;
        description = "Volume server HTTP port.";
      };

      filerPort = mkOption {
        type = types.ints.positive;
        default = 8888;
        description = "Filer HTTP port.";
      };

      defaultReplication = mkOption {
        type = types.str;
        default = "001";
        description = "Default replication policy for new files.";
      };

      autoBootstrap = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically enable -raftBootstrap when there is a single master.";
      };

      bootstrapMaster = mkOption {
        type = types.bool;
        default = false;
        description = "Manually enable -raftBootstrap for this master node.";
      };
    };

    master = {
      metaDir = mkOption {
        type = types.str;
        default = "/var/lib/seaweedfs/master";
        description = "Directory for master metadata.";
      };
    };

    volume = {
      disks = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Device paths (prefer /dev/disk/by-id/...) to use for SeaweedFS volumes.";
      };

      mountBase = mkOption {
        type = types.str;
        default = "/mnt/seaweedfs";
        description = "Base directory for SeaweedFS volume mounts when disks are managed.";
      };

      dataDirs = mkOption {
        type = types.listOf types.str;
        default = [ "/var/lib/seaweedfs/volume" ];
        description = "Directories for volume data.";
      };

      filesystem = mkOption {
        type = types.str;
        default = "xfs";
        description = "Filesystem to create on managed disks (e.g., xfs, ext4).";
      };

      formatIfMissing = mkOption {
        type = types.bool;
        default = false;
        description = "Format and partition disks if they are uninitialized.";
      };

      encryption = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable per-disk LUKS encryption for volume disks.";
        };

        namePrefix = mkOption {
          type = types.str;
          default = "seaweed";
          description = "Prefix for LUKS mapper device names.";
        };

        keyFiles = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "Key files for each disk, keyed by disk id (baseNameOf the disk path).";
        };

        allowDiscards = mkOption {
          type = types.bool;
          default = true;
          description = "Allow discards for encrypted SSDs.";
        };
      };

      maxVolumes = mkOption {
        type = types.ints.positive;
        default = 8;
        description = "Maximum number of volumes on this node.";
      };

      publicUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Publicly reachable URL for this volume server (optional).";
      };
    };

    filer = {
      storeDir = mkOption {
        type = types.str;
        default = "/var/lib/seaweedfs/filer";
        description = "Embedded filer store directory.";
      };

      enableS3 = mkOption {
        type = types.bool;
        default = false;
        description = "Enable the SeaweedFS S3 gateway on this filer.";
      };

      s3Port = mkOption {
        type = types.ints.positive;
        default = 8333;
        description = "S3 gateway HTTP port.";
      };

      configText = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "Optional /etc/seaweedfs/filer.toml contents.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = roles != [ ];
        message = "lukasf.seaweedfs: no roles set (set roles or cluster.nodes.<nodeName>.roles).";
      }
      {
        assertion = nodeAddress != null && nodeAddress != "";
        message = "lukasf.seaweedfs: nodeAddress must be set or derivable.";
      }
      {
        assertion = (!hasRole "volume" && !hasRole "filer") || masterAddresses != [ ];
        message = "lukasf.seaweedfs: volume/filer roles require master servers.";
      }
      {
        assertion =
          cfg.volume.disks == [ ] || lib.all (d: lib.hasPrefix "/dev/disk/by-id/" d) cfg.volume.disks;
        message = "lukasf.seaweedfs: volume.disks should use /dev/disk/by-id paths so partition names are stable.";
      }
      {
        assertion = (!cfg.volume.encryption.enable) || lib.all (entry: entry.keyFile != null) diskEntries;
        message = "lukasf.seaweedfs: encryption enabled but missing keyFiles for one or more disks.";
      }
    ];

    users.groups.seaweedfs = { };
    users.users.seaweedfs = {
      isSystemUser = true;
      group = "seaweedfs";
    };

    systemd.tmpfiles.rules =
      (optional (hasRole "master") "d ${cfg.master.metaDir} 0750 seaweedfs seaweedfs -")
      ++ (lib.optionals (hasRole "volume") (
        map (dir: "d ${dir} 0750 seaweedfs seaweedfs -") volumeDataDirs
      ))
      ++ (optional (hasRole "filer") "d ${cfg.filer.storeDir} 0750 seaweedfs seaweedfs -");

    environment.etc = optionalAttrs (cfg.filer.configText != null) {
      "seaweedfs/filer.toml".text = cfg.filer.configText;
    };

    systemd.services = lib.mkMerge [
      (lib.optionalAttrs (hasRole "master") {
        seaweedfs-master = {
          description = "SeaweedFS master";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            User = "seaweedfs";
            Group = "seaweedfs";
            Restart = "on-failure";
            ExecStart = concatStringsSep " " (
              [
                weed
                "master"
                "-ip=${nodeAddress}"
                "-ip.bind=${cfg.bindAddress}"
                "-port=${toString cfg.cluster.masterPort}"
                "-mdir=${cfg.master.metaDir}"
                "-defaultReplication=${cfg.cluster.defaultReplication}"
              ]
              ++ optional (masterPeers != "") "-peers=${masterPeers}"
              ++ optional bootstrapMaster "-raftBootstrap"
            );
          };
        };
      })
      (lib.optionalAttrs (hasRole "volume") {
        seaweedfs-volume = {
          description = "SeaweedFS volume server";
          after = [
            "local-fs.target"
            "network-online.target"
          ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          unitConfig = {
            RequiresMountsFor = volumeDataDirs;
          };
          serviceConfig = {
            User = "seaweedfs";
            Group = "seaweedfs";
            Restart = "on-failure";
            ExecStart = concatStringsSep " " (
              [
                weed
                "volume"
                "-ip=${nodeAddress}"
                "-ip.bind=${cfg.bindAddress}"
                "-port=${toString cfg.cluster.volumePort}"
                "-dir=${volumeDirs}"
                "-max=${toString cfg.volume.maxVolumes}"
                "-mserver=${masterList}"
              ]
              ++ optional (cfg.volume.publicUrl != null) "-publicUrl=${cfg.volume.publicUrl}"
            );
          };
        };
      })
      (lib.optionalAttrs (hasRole "filer") {
        seaweedfs-filer = {
          description = "SeaweedFS filer";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            User = "seaweedfs";
            Group = "seaweedfs";
            Restart = "on-failure";
            ExecStart = concatStringsSep " " (
              [
                weed
                "filer"
                "-ip=${nodeAddress}"
                "-ip.bind=${cfg.bindAddress}"
                "-port=${toString cfg.cluster.filerPort}"
                "-master=${masterList}"
                "-defaultStoreDir=${cfg.filer.storeDir}"
              ]
              ++ optional cfg.filer.enableS3 "-s3"
              ++ optional cfg.filer.enableS3 "-s3.port=${toString cfg.filer.s3Port}"
            );
          };
        };
      })
      (lib.optionalAttrs (cfg.volume.formatIfMissing && cfg.volume.disks != [ ]) {
        seaweedfs-format-disks = {
          description = "SeaweedFS disk preparation";
          after = [ "systemd-udev-settle.service" ];
          wants = [ "systemd-udev-settle.service" ];
          before =
            (optional (hasRole "volume") "seaweedfs-volume.service")
            ++ (lib.optionals cfg.volume.encryption.enable (
              map (entry: "seaweedfs-cryptsetup-${entry.diskId}.service") diskEntries
            ));
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart =
              let
                allowDiscards = optionalString cfg.volume.encryption.allowDiscards "--allow-discards";
              in
              pkgs.writeShellScript "seaweedfs-format-disks" ''
                set -euo pipefail
                for disk in ${lib.concatStringsSep " " cfg.volume.disks}; do
                  disk_id="$(${pkgs.coreutils}/bin/basename "$disk")"
                  part="$disk-part1"
                  if [ ! -b "$part" ]; then
                    ${pkgs.gptfdisk}/bin/sgdisk --clear "$disk"
                    ${pkgs.gptfdisk}/bin/sgdisk --new=1:0:0 --typecode=1:8300 "$disk"
                    ${pkgs.parted}/bin/partprobe "$disk"
                    ${pkgs.systemd}/bin/udevadm settle
                  fi

                  target="$part"
                  if ${lib.boolToString cfg.volume.encryption.enable}; then
                    key_file_map="${
                      lib.concatStringsSep " " (map (entry: "${entry.diskId}:${entry.keyFile or ""}") diskEntries)
                    }"
                    key="$(printf '%s\n' "$key_file_map" | ${pkgs.gnugrep}/bin/grep "^\${disk_id}:" | ${pkgs.coreutils}/bin/cut -d: -f2-)"
                    if [ -z "$key" ]; then
                      echo "Missing key file for $disk_id" >&2
                      exit 1
                    fi
                    if ! ${pkgs.cryptsetup}/bin/cryptsetup isLuks "$part" >/dev/null 2>&1; then
                      ${pkgs.cryptsetup}/bin/cryptsetup -q luksFormat "$part" --key-file "$key"
                    fi
                    mapper="/dev/mapper/${cfg.volume.encryption.namePrefix}-$disk_id"
                    if [ ! -e "$mapper" ]; then
                      ${pkgs.cryptsetup}/bin/cryptsetup open "$part" "${cfg.volume.encryption.namePrefix}-$disk_id" --key-file "$key" ${allowDiscards}
                    fi
                    target="$mapper"
                  fi

                  if ! ${pkgs.util-linux}/bin/blkid -o value -s TYPE "$target" >/dev/null 2>&1; then
                    case "${cfg.volume.filesystem}" in
                      xfs)
                        ${pkgs.xfsprogs}/bin/mkfs.xfs -f "$target"
                        ;;
                      ext4)
                        ${pkgs.e2fsprogs}/bin/mkfs.ext4 -F "$target"
                        ;;
                      *)
                        echo "Unsupported filesystem: ${cfg.volume.filesystem}" >&2
                        exit 1
                        ;;
                    esac
                  fi
                done
              '';
          };
          wantedBy = [ "multi-user.target" ];
        };
      })
      (lib.optionalAttrs cfg.volume.encryption.enable (
        lib.listToAttrs (
          map (entry: {
            name = "seaweedfs-cryptsetup-${entry.diskId}";
            value = {
              description = "SeaweedFS LUKS unlock for ${entry.diskId}";
              after = [
                "network-online.target"
              ]
              ++ optional cfg.volume.formatIfMissing "seaweedfs-format-disks.service";
              wants = [ "network-online.target" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart =
                  let
                    allowDiscards = optionalString cfg.volume.encryption.allowDiscards "--allow-discards";
                  in
                  "${pkgs.cryptsetup}/bin/cryptsetup open ${entry.partDevice} ${entry.mapperName} --key-file ${entry.keyFile} ${allowDiscards}";
                ExecStop = "${pkgs.cryptsetup}/bin/cryptsetup close ${entry.mapperName}";
              };
            };
          }) diskEntries
        )
      ))
    ];

    fileSystems = lib.mkIf (cfg.volume.disks != [ ]) (
      lib.listToAttrs (
        map (entry: {
          name = entry.mountPoint;
          value = {
            device = if cfg.volume.encryption.enable then entry.mapperDevice else entry.partDevice;
            fsType = cfg.volume.filesystem;
            options = [
              "noatime"
              "nodiratime"
              "nofail"
              "x-systemd.device-timeout=1min"
            ]
            ++ optional (cfg.volume.encryption.enable) "x-systemd.requires=seaweedfs-cryptsetup-${entry.diskId}.service"
            ++ optional (cfg.volume.encryption.enable) "x-systemd.after=seaweedfs-cryptsetup-${entry.diskId}.service";
          };
        }) diskEntries
      )
    );

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall (
      (optional (hasRole "master") cfg.cluster.masterPort)
      ++ (optional (hasRole "volume") cfg.cluster.volumePort)
      ++ (optional (hasRole "filer") cfg.cluster.filerPort)
      ++ (optional (hasRole "filer" && cfg.filer.enableS3) cfg.filer.s3Port)
    );
  };
}
