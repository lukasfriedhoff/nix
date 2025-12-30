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

  weed = "${pkgs.seaweedfs}/bin/weed";
  volumeDirs = concatStringsSep "," cfg.volume.dataDirs;
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
      dataDirs = mkOption {
        type = types.listOf types.str;
        default = [ "/var/lib/seaweedfs/volume" ];
        description = "Directories for volume data.";
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
    ];

    users.groups.seaweedfs = { };
    users.users.seaweedfs = {
      isSystemUser = true;
      group = "seaweedfs";
    };

    systemd.tmpfiles.rules =
      (optional (hasRole "master") "d ${cfg.master.metaDir} 0750 seaweedfs seaweedfs -")
      ++ (lib.optionals (hasRole "volume") (
        map (dir: "d ${dir} 0750 seaweedfs seaweedfs -") cfg.volume.dataDirs
      ))
      ++ (optional (hasRole "filer") "d ${cfg.filer.storeDir} 0750 seaweedfs seaweedfs -");

    environment.etc = optionalAttrs (cfg.filer.configText != null) {
      "seaweedfs/filer.toml".text = cfg.filer.configText;
    };

    systemd.services.seaweedfs-master = mkIf (hasRole "master") {
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

    systemd.services.seaweedfs-volume = mkIf (hasRole "volume") {
      description = "SeaweedFS volume server";
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

    systemd.services.seaweedfs-filer = mkIf (hasRole "filer") {
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

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall (
      (optional (hasRole "master") cfg.cluster.masterPort)
      ++ (optional (hasRole "volume") cfg.cluster.volumePort)
      ++ (optional (hasRole "filer") cfg.cluster.filerPort)
      ++ (optional (hasRole "filer" && cfg.filer.enableS3) cfg.filer.s3Port)
    );
  };
}
