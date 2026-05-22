{
  config,
  lib,
  pkgs,
  secrets ? { },
  ...
}:

let
  cfg = config.lukasf.ceph;
  primaryRoot = secrets.primary or secrets.root or null;
  cephSecretsRoot = secrets.ceph or null;
  resolveSecret =
    path:
    if path == null then
      null
    else if lib.hasPrefix "/" path then
      path
    else if cephSecretsRoot != null then
      "${cephSecretsRoot}/${path}"
    else if primaryRoot != null then
      "${primaryRoot}/${path}"
    else
      throw "lukasf.ceph: relative secret '${path}' requires secrets.ceph or secrets.primary/root";
  sanitizeName = value: lib.replaceStrings [ "/" "." ":" " " ] [ "-" "-" "-" "-" ] value;
  lockboxEntries = map (
    entry:
    let
      baseName =
        if entry.name != null && entry.name != "" then entry.name else builtins.baseNameOf entry.device;
      name = sanitizeName baseName;
    in
    entry
    // {
      inherit name;
      secretName = "ceph-osd-lockbox-${name}";
    }
  ) cfg.osd.lockboxKeys;
  systemctlShim = pkgs.writeShellScriptBin "systemctl" ''
    set -euo pipefail
    runtime=0
    for arg in "$@"; do
      if [ "$arg" = "enable" ] || [ "$arg" = "reenable" ] || [ "$arg" = "disable" ]; then
        runtime=1
        break
      fi
    done
    if [ "$runtime" -eq 1 ]; then
      exec ${pkgs.systemd}/bin/systemctl --runtime "$@"
    else
      exec ${pkgs.systemd}/bin/systemctl "$@"
    fi
  '';
  cephadmArgs = lib.flatten [
    (lib.optional (cfg.cephadm.unitDir != null) "--unit-dir")
    (lib.optional (cfg.cephadm.unitDir != null) cfg.cephadm.unitDir)
  ];
  cephadmPath = with pkgs; [
    systemctlShim
    bash
    coreutils
    cryptsetup
    findutils
    gawk
    gptfdisk
    gnugrep
    gnused
    iproute2
    iputils
    jq
    lvm2
    parted
    podman
    util-linux
  ];
  cephadmBinPath = lib.makeBinPath cephadmPath;
  cephVolumePath = with pkgs; [
    bash
    coreutils
    cryptsetup
    findutils
    gawk
    gptfdisk
    gnugrep
    gnused
    jq
    lvm2
    parted
    systemd
    util-linux
  ];
  pythonWithCephadmDeps = pkgs.python3.withPackages (ps: [
    ps.asyncssh
    ps.bcrypt
    ps.certifi
    ps.cherrypy
    ps.cryptography
    ps.idna
    ps.jinja2
    ps.prettytable
    ps.pyopenssl
    ps.pyyaml
    ps.requests
    ps.six
    ps.urllib3
    ps.werkzeug
  ]);
  pythonSite = pkgs.python3.sitePackages;
  cephRuntimePkg =
    if cfg.wrapRuntimeDeps then
      pkgs.callPackage ../../../pkgs/ceph-wrapped { ceph = cfg.package; }
    else
      cfg.package;
  cephWithCephadmDeps = pkgs.symlinkJoin {
    name = "${cephRuntimePkg.name}-with-cephadm-deps";
    paths = [ cephRuntimePkg ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      if [ -x "$out/bin/cephadm" ]; then
        wrapProgram "$out/bin/cephadm" \
          --set PYTHONPATH "${pythonWithCephadmDeps}/${pythonSite}"
      fi
    '';
  };
  cephPkg = if cfg.cephadm.wrapCephadm then cephWithCephadmDeps else cephRuntimePkg;
  cephadmBin = pkgs.writeShellScriptBin "cephadm-with-deps" ''
    export PYTHONPATH="${pythonWithCephadmDeps}/${pythonSite}:''${PYTHONPATH:-}"
    export PATH="${cephadmBinPath}:''${PATH:-}"
    exec ${cephPkg}/bin/cephadm ${lib.escapeShellArgs cephadmArgs} "$@"
  '';
  cephadm = "${cephadmBin}/bin/cephadm-with-deps";
  cephadmOrch = pkgs.writeShellScriptBin "cephadm-orch" ''
    export PYTHONPATH="${pythonWithCephadmDeps}/${pythonSite}:''${PYTHONPATH:-}"
    export PATH="${cephadmBinPath}:''${PATH:-}"
    exec ${cephPkg}/bin/cephadm ${lib.escapeShellArgs cephadmArgs} "$@"
  '';
  cephadmMgrPathHost = "/run/ceph/cephadm-orch";
  cephadmMgrPathContainer = "/var/run/ceph/cephadm-orch";
  cephadmMgrWrapper = pkgs.writeTextFile {
    name = "cephadm-orch-wrapper.py";
    executable = true;
    text = ''
      #!/usr/bin/env python3
      import os
      import sys

      args = sys.argv[1:]
      os.environ["PATH"] = "${cephadmBinPath}:" + os.environ.get("PATH", "")
      if "--unit-dir" not in args:
          args = ["--unit-dir", "${cfg.cephadm.unitDir}"] + args
      use_sudo = ${if cfg.cephadm.useSudo then "True" else "False"}
      sudo_cmd = "/run/wrappers/bin/sudo"
      if use_sudo and os.geteuid() != 0:
          os.execv(sudo_cmd, [sudo_cmd, "-n", "${cephadm}"] + args)
      os.execv("${cephadm}", ["${cephadm}"] + args)
    '';
  };
  cephadmMgrContainerWrapper = pkgs.writeTextFile {
    name = "cephadm-orch-container-wrapper.py";
    executable = true;
    text = ''
      #!/usr/bin/env python3
      import os
      import sys

      args = sys.argv[1:]
      if "--unit-dir" not in args:
          args = ["--unit-dir", "${cfg.cephadm.unitDir}"] + args
      cephadm = "/run/current-system/sw/bin/cephadm"
      if not os.path.exists(cephadm):
          cephadm = "/usr/sbin/cephadm"
      os.execv(cephadm, [cephadm] + args)
    '';
  };
  python = "${pkgs.python3}/bin/python3";
  inherit (config.networking) hostName;
  osdHost = cfg.osd.host;
  isNumericHost = host: builtins.match "^[0-9.:]+$" host != null;
  formatMonHost =
    host: port:
    if isNumericHost host then "v2:${host}:${toString port}" else "${host}:${toString port}";
  formatMonHosts = hosts: port: lib.concatMapStringsSep "," (host: formatMonHost host port) hosts;
  cephfsPoolModule = lib.types.submodule (_: {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Pool name.";
      };

      size = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "Replication size.";
      };

      minSize = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Minimum replication size.";
      };

      pgNum = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "PG count.";
      };
    };
  });
  dedupPools =
    pools:
    (builtins.foldl'
      (
        acc: pool:
        if lib.elem pool.name acc.names then
          acc
        else
          {
            names = acc.names ++ [ pool.name ];
            pools = acc.pools ++ [ pool ];
          }
      )
      {
        names = [ ];
        pools = [ ];
      }
      pools
    ).pools;
  cephfsPools =
    let
      poolWithApp = pool: pool // { application = "cephfs"; };
      poolsForFs = fs: [ (poolWithApp fs.metadataPool) ] ++ map poolWithApp fs.dataPools;
    in
    lib.concatMap poolsForFs cfg.cephfs;
  rgwPoolPrefix =
    if cfg.rgw.poolPrefix != null && cfg.rgw.poolPrefix != "" then
      cfg.rgw.poolPrefix
    else if cfg.rgw.bucketPrefix != null && cfg.rgw.bucketPrefix != "" then
      cfg.rgw.bucketPrefix
    else
      "rgw";
  rgwPools =
    if cfg.rgw.enable then
      let
        poolSettings = cfg.rgw.pool;
        poolSuffixes = [
          "rgw.control"
          "rgw.meta"
          "rgw.log"
          "rgw.buckets.index"
          "rgw.buckets.data"
          "rgw.buckets.non-ec"
          "rgw.buckets.extra"
          "rgw.reshard"
          "rgw.gc"
          "rgw.lc"
          "rgw.usage"
          "rgw.users.keys"
          "rgw.users.email"
          "rgw.users.swift"
          "rgw.users.uid"
        ];
        poolNames = [ ".rgw.root" ] ++ map (suffix: "${rgwPoolPrefix}.${suffix}") poolSuffixes;
      in
      map (name: {
        inherit name;
        application = "rgw";
        inherit (poolSettings) size;
        inherit (poolSettings) minSize;
        inherit (poolSettings) pgNum;
      }) poolNames
    else
      [ ];
  rgwUsers = map (
    user:
    let
      userName = sanitizeName user.name;
    in
    user
    // {
      accessSecretName = "ceph-rgw-${userName}-access-key";
      secretSecretName = "ceph-rgw-${userName}-secret-key";
    }
  ) cfg.rgw.users;
  rgwBucketPrefix =
    if cfg.rgw.bucketPrefix != null && cfg.rgw.bucketPrefix != "" then cfg.rgw.bucketPrefix else null;
  rgwBuckets = map (
    bucket:
    bucket
    // {
      fullName = if rgwBucketPrefix == null then bucket.name else "${rgwBucketPrefix}-${bucket.name}";
    }
  ) cfg.rgw.buckets;
  rgwBucketEntries = map (
    bucket:
    let
      owner = lib.findFirst (user: user.name == bucket.user) null rgwUsers;
    in
    bucket
    // {
      ownerAccessSecretName = owner.accessSecretName;
      ownerSecretSecretName = owner.secretSecretName;
    }
  ) rgwBuckets;
  rgwSecretEntries = lib.concatMap (user: [
    {
      name = user.accessSecretName;
      file = user.accessKeyFile;
    }
    {
      name = user.secretSecretName;
      file = user.secretKeyFile;
    }
  ]) rgwUsers;
  rgwPath = cephadmPath ++ [ pkgs.awscli2 ];
  allPools = dedupPools (cfg.pools ++ cephfsPools ++ rgwPools);
in
{
  options.lukasf.ceph = {
    enable = lib.mkEnableOption "Ceph (cephadm/ceph-volume)";

    package = lib.mkPackageOption pkgs "ceph" { };

    user = {
      uid = lib.mkOption {
        type = lib.types.int;
        default = 167;
        description = "UID for the ceph user (matches cephadm container user).";
      };

      gid = lib.mkOption {
        type = lib.types.int;
        default = 167;
        description = "GID for the ceph group (matches cephadm container group).";
      };
    };

    wrapRuntimeDeps = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Wrap Ceph helper binaries with a PATH that includes runtime tools
        like modprobe, mount/fusermount, lsblk/lvs, and smartctl.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the default Ceph ports in the firewall.";
    };

    monHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Default monitor hosts/IPs used for client mon_host entries.";
    };

    monPort = lib.mkOption {
      type = lib.types.int;
      default = 3300;
      description = "Default monitor port for client mon_host entries.";
    };

    bootstrap = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Bootstrap the cluster with cephadm if no cluster is present.";
      };

      monIp = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Monitor IP address for cephadm bootstrap.";
      };

      fsid = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional cluster FSID (UUID) for bootstrap.";
      };

      publicNetwork = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Public network CIDR(s) for Ceph.";
      };

      clusterNetwork = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Cluster network CIDR(s) for Ceph.";
      };

      singleHostDefaults = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Apply cephadm single-host defaults (replication size=1).";
      };

      skipDashboard = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Skip deploying the dashboard during bootstrap.";
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra arguments passed to cephadm bootstrap.";
      };
    };

    cephadm = {
      unitDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "/run/systemd/system";
        description = "Directory where cephadm installs systemd units on the host.";
      };

      wrapCephadm = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Wrap cephadm with Python dependencies to avoid missing-module errors.";
      };

      useSudo = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run cephadm via sudo when invoked by ceph-mgr to avoid rootless podman ownership issues.";
      };
    };

    pools = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule (_: {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Pool name.";
            };

            application = lib.mkOption {
              type = lib.types.str;
              default = "rbd";
              description = "Ceph application for the pool (e.g. rbd, cephfs, rgw).";
            };

            size = lib.mkOption {
              type = lib.types.int;
              default = 3;
              description = "Replication size.";
            };

            minSize = lib.mkOption {
              type = lib.types.nullOr lib.types.int;
              default = null;
              description = "Minimum replication size.";
            };

            pgNum = lib.mkOption {
              type = lib.types.nullOr lib.types.int;
              default = null;
              description = "PG count.";
            };
          };
        })
      );
      default = [ ];
      description = "Ceph pools to create and configure.";
    };

    cephfs = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule (_: {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "CephFS filesystem name.";
            };

            metadataPool = lib.mkOption {
              type = cephfsPoolModule;
              description = "Metadata pool configuration (application forced to cephfs).";
            };

            dataPools = lib.mkOption {
              type = lib.types.listOf cephfsPoolModule;
              default = [ ];
              description = "Data pool configurations (first entry becomes the primary data pool).";
            };

            mds = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Manage MDS placement for this filesystem.";
              };

              count = lib.mkOption {
                type = lib.types.int;
                default = 1;
                description = "Number of active MDS daemons (also sets max_mds).";
              };

              standbyCount = lib.mkOption {
                type = lib.types.nullOr lib.types.int;
                default = null;
                description = "Desired standby MDS count (standby_count_wanted).";
              };

              placement = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Ceph orchestrator placement string for MDS daemons (overrides count when set).";
              };
            };
          };
        })
      );
      default = [ ];
      description = "CephFS filesystems to create and configure.";
    };

    rgw = {
      enable = lib.mkEnableOption "Ceph RGW (RADOS Gateway) S3 endpoint";

      serviceId = lib.mkOption {
        type = lib.types.str;
        default = "rgw";
        description = "Ceph orch service id used for the RGW deployment.";
      };

      realm = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "RGW realm name (set explicitly for multi-site readiness).";
      };

      zonegroup = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "RGW zonegroup name (set explicitly for multi-site readiness).";
      };

      zone = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "RGW zone name (set explicitly for multi-site readiness).";
      };

      placement = lib.mkOption {
        type = lib.types.str;
        default = "1";
        description = "Ceph orchestrator placement string for RGW daemons.";
      };

      endpoint = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "RGW endpoint URL used for realm/zonegroup/zone endpoints.";
      };

      region = lib.mkOption {
        type = lib.types.str;
        default = "us-east-1";
        description = "RGW region used by S3 clients and bucket creation.";
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 7480;
        description = "RGW HTTP port.";
      };

      sslPort = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "RGW HTTPS port (optional).";
      };

      poolPrefix = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Prefix for RGW internal pools (e.g. homelab).";
      };

      pool = {
        size = lib.mkOption {
          type = lib.types.int;
          default = 3;
          description = "Replication size for RGW pools.";
        };

        minSize = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "Minimum replication size for RGW pools.";
        };

        pgNum = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "PG count for RGW pools.";
        };
      };

      bucketPrefix = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Prefix applied to RGW buckets created by this module.";
      };

      users = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule (_: {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "RGW user ID.";
              };

              displayName = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Human-friendly RGW user display name.";
              };

              accessKeyFile = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "SOPS secret file containing the RGW access key.";
              };

              secretKeyFile = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "SOPS secret file containing the RGW secret key.";
              };

              caps = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Optional RGW caps to apply to this user.";
              };
            };
          })
        );
        default = [ ];
        description = "RGW users to create with fixed credentials.";
      };

      buckets = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule (_: {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "Bucket short name (prefix applied if configured).";
              };

              user = lib.mkOption {
                type = lib.types.str;
                description = "RGW user ID that owns the bucket.";
              };
            };
          })
        );
        default = [ ];
        description = "RGW buckets to create.";
      };
    };

    osd = {
      provisioner = lib.mkOption {
        type = lib.types.enum [
          "cephadm"
          "ceph-volume"
        ];
        default = "cephadm";
        description = "Provision OSDs via cephadm or with ceph-volume + custom systemd units.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = hostName;
        description = "Ceph orch host name used when adding OSDs.";
      };
      devices = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "List of device paths (prefer /dev/disk/by-id/*) to provision as OSDs.";
      };

      method = lib.mkOption {
        type = lib.types.enum [
          "raw"
          "lvm"
        ];
        default = "raw";
        description = "OSD provisioning method used by cephadm.";
      };

      encrypted = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use dm-crypt for OSDs managed by cephadm.";
      };

      deviceClass = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "hdd"
            "ssd"
            "nvme"
          ]
        );
        default = null;
        description = ''
          Optional CRUSH device class to enforce for local OSDs after activation.
          Useful for virtualized OSDs where rotational hints are misleading.
        '';
      };

      zapDevices = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Zap OSD devices before provisioning (destructive).";
      };

      autoProvision = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Automatically provision OSDs on the specified devices.";
      };

      lockboxKeys = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              device = lib.mkOption {
                type = lib.types.str;
                description = "Device path (prefer /dev/disk/by-id/*) this lockbox key is for.";
              };
              secretKeyFile = lib.mkOption {
                type = lib.types.str;
                description = ''
                  Path to the SOPS-encrypted lockbox key file (relative to secrets.ceph
                  or secrets.primary/root, or absolute).
                '';
              };
              name = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Optional name for this key entry (defaults to device basename).";
              };
            };
          }
        );
        default = [ ];
        description = ''
          Mapping of OSD devices to their SOPS-encrypted lockbox keys.
          When a key is provided, it will be imported into the OSD's lockbox
          keyring directory during activation, enabling encrypted OSDs to be
          activated without re-creating keys.
        '';
        example = lib.literalExpression ''
          [
            {
              device = "/dev/disk/by-id/ata-SAMSUNG_...";
              secretKeyFile = "ceph/<fsid>/osd-lockbox/ata-SAMSUNG_....key";
            }
          ]
        '';
      };
    };

    backup = {
      enable = lib.mkEnableOption "Ceph key backups";

      secretKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Path to the SOPS-encrypted backup key (absolute or relative to
          <option>secrets.ceph</option> when set, otherwise
          <option>secrets.primary</option>/<option>secrets.root</option>).
        '';
      };

      destination = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/ceph/backup";
        description = "Directory where encrypted key backups are written.";
      };

      retentionDays = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Delete backups older than this many days.";
      };

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "systemd OnCalendar value for the backup timer.";
      };
    };

    monUpdate = {
      enable = lib.mkEnableOption "Update monitor addresses in the monmap";

      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Monitor name to update (defaults to the single mon in the monmap).";
      };

      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Monitor IP address to set for the monmap entry.";
      };

      legacyAddress = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional legacy monitor IP to add to loopback during the update.";
      };

      legacyPrefixLength = lib.mkOption {
        type = lib.types.int;
        default = 32;
        description = "Prefix length for the temporary legacy monitor IP.";
      };

      v1Port = lib.mkOption {
        type = lib.types.int;
        default = 6789;
        description = "Legacy v1 monitor port.";
      };

      v2Port = lib.mkOption {
        type = lib.types.int;
        default = 3300;
        description = "v2 monitor port.";
      };
    };

    client = {
      enable = lib.mkEnableOption "Ceph client configuration";

      clusterName = lib.mkOption {
        type = lib.types.str;
        default = "ceph";
        description = "Ceph cluster name used in the generated config.";
      };

      fsid = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional cluster FSID to pin clients to a specific cluster.";
      };

      monHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = config.lukasf.ceph.monHosts;
        description = "Monitor hosts or IPs used to populate mon_host in ceph.conf.";
      };

      monPort = lib.mkOption {
        type = lib.types.int;
        default = config.lukasf.ceph.monPort;
        description = "Monitor port for mon_host entries (v2 default is 3300).";
      };

      publicNetwork = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional public network CIDR(s) for clients.";
      };

      confFile = lib.mkOption {
        type = lib.types.str;
        default = "/etc/ceph/ceph.conf";
        description = "Path where the client ceph.conf is written.";
      };

      extraConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Extra config lines appended to the client ceph.conf.";
      };
    };

    healthCheck = {
      enable = lib.mkEnableOption "Ceph health check service";

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "systemd OnCalendar value for health check timer (default: daily).";
      };

      runOnActivation = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run health check after NixOS activation (config changes).";
      };

      warnIsFailure = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Treat HEALTH_WARN as service failure (useful for alerting).";
      };

      checkPools = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include pool status in health check output.";
      };

      checkOsds = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include OSD status in health check output.";
      };

      checkLibvirt = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Check libvirt storage pool status (requires libvirtd).";
      };

      libvirtPools = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "ceph-images"
          "ceph-vmdisks"
        ];
        description = "Libvirt storage pools to check (empty = all pools).";
      };

      outputFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "/run/ceph/health-status.json";
        description = "Write health status to this JSON file (null to disable).";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = (!cfg.bootstrap.enable) || (cfg.bootstrap.monIp != null && cfg.bootstrap.monIp != "");
          message = "lukasf.ceph.bootstrap.monIp must be set when bootstrap is enabled.";
        }
        {
          assertion = (!cfg.backup.enable) || (cfg.backup.secretKeyFile != null);
          message = "lukasf.ceph.backup.secretKeyFile must be set when backups are enabled.";
        }
        {
          assertion = lib.all (fs: fs.dataPools != [ ]) cfg.cephfs;
          message = "lukasf.ceph.cephfs entries must define at least one data pool.";
        }
        {
          assertion = (!cfg.cephadm.useSudo) || config.security.sudo.enable;
          message = "lukasf.ceph.cephadm.useSudo requires security.sudo.enable = true.";
        }
        {
          assertion =
            (!cfg.rgw.enable)
            || lib.all (user: user.accessKeyFile != null && user.secretKeyFile != null) cfg.rgw.users;
          message = "lukasf.ceph.rgw.users entries must set accessKeyFile and secretKeyFile.";
        }
        {
          assertion =
            (!cfg.rgw.enable)
            || lib.all (bucket: lib.any (user: user.name == bucket.user) cfg.rgw.users) cfg.rgw.buckets;
          message = "lukasf.ceph.rgw.buckets entries must reference a user listed in lukasf.ceph.rgw.users.";
        }
      ];

      environment.systemPackages = [
        cephPkg
        pkgs.python3
        pkgs.cryptsetup
        pkgs.lvm2
        cephadmBin
        cephadmOrch
      ];

      virtualisation.podman.enable = true;

      users.groups.ceph = {
        inherit (cfg.user) gid;
      };
      users.users.ceph = {
        isSystemUser = true;
        inherit (cfg.user) uid;
        group = "ceph";
        home = "/var/lib/ceph";
        shell = "${pkgs.shadow}/bin/nologin";
      };

      systemd.services.ceph-user-sync = {
        description = "Ensure Ceph user/group IDs match the configured values";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [
          pkgs.shadow
          pkgs.coreutils
          pkgs.glibc.getent
          pkgs.procps
          pkgs.systemd
        ];
        script = ''
          set -euo pipefail

          target_uid=${toString cfg.user.uid}
          target_gid=${toString cfg.user.gid}
          stopped_units=0
          active_ceph_units_file="$(mktemp)"
          trap 'rm -f "$active_ceph_units_file"' EXIT

          stop_ceph_units() {
            systemctl list-units \
              --type=service \
              --state=active \
              --no-legend \
              'ceph-mon@*.service' \
              'ceph-mgr@*.service' \
              'ceph-osd@*.service' \
              'ceph-mds@*.service' \
              'ceph-radosgw@*.service' \
              | awk '{print $1}' > "$active_ceph_units_file" || true
            if [ -s "$active_ceph_units_file" ]; then
              xargs -r systemctl stop < "$active_ceph_units_file" >/dev/null 2>&1 || true
              stopped_units=1
            fi
          }

          start_ceph_units() {
            if [ -s "$active_ceph_units_file" ]; then
              xargs -r systemctl start < "$active_ceph_units_file" >/dev/null 2>&1 || true
            fi
          }

          stop_ceph_processes() {
            if pgrep -u ceph >/dev/null 2>&1; then
              pkill -u ceph >/dev/null 2>&1 || true
              for _ in 1 2 3; do
                if ! pgrep -u ceph >/dev/null 2>&1; then
                  return 0
                fi
                sleep 1
              done
              pkill -KILL -u ceph >/dev/null 2>&1 || true
            fi
          }

          current_uid="$(id -u ceph 2>/dev/null || true)"
          current_gid="$(getent group ceph | cut -d: -f3 || true)"

          if [ -z "$current_uid" ] || [ -z "$current_gid" ]; then
            exit 0
          fi

          if [ "$current_gid" != "$target_gid" ]; then
            if getent group "$target_gid" | grep -qv '^ceph:'; then
              echo "ceph-user-sync: gid $target_gid already used by another group" >&2
            else
              groupmod -g "$target_gid" ceph
            fi
          fi

          if [ "$current_uid" != "$target_uid" ]; then
            if getent passwd "$target_uid" | grep -qv '^ceph:'; then
              echo "ceph-user-sync: uid $target_uid already used by another user" >&2
            else
              if ! usermod -u "$target_uid" -g "$target_gid" ceph; then
                echo "ceph-user-sync: usermod failed; stopping ceph services and retrying" >&2
                stop_ceph_units
                stop_ceph_processes
                usermod -u "$target_uid" -g "$target_gid" ceph || true
              fi
            fi
          fi

          for dir in /var/lib/ceph /var/log/ceph /run/ceph; do
            if [ -d "$dir" ]; then
              chown -R ceph:ceph "$dir" || true
            fi
          done

          if [ "$stopped_units" -eq 1 ]; then
            start_ceph_units
          fi
        '';
      };

      systemd.services.ceph-fsid-perms = lib.mkIf (cfg.bootstrap.fsid != null) {
        description = "Ensure Ceph FSID directory ownership";
        after = [ "ceph-user-sync.service" ];
        wants = [ "ceph-user-sync.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig.Type = "oneshot";
        path = [
          pkgs.coreutils
          pkgs.systemd
        ];
        script = ''
          set -euo pipefail
          fs_root="/var/lib/ceph/${cfg.bootstrap.fsid}"
          if [ -d "$fs_root" ]; then
            owner="$(stat -c '%U:%G' "$fs_root" 2>/dev/null || true)"
            if [ "$owner" != "ceph:ceph" ]; then
              chown -R ceph:ceph "$fs_root" || true
              chmod 0755 "$fs_root" || true
              ${pkgs.systemd}/bin/systemctl try-restart 'ceph-mon@*.service' 'ceph-mgr@*.service' || true
            fi
          fi
        '';
      };

      systemd.paths.ceph-fsid-perms = lib.mkIf (cfg.bootstrap.fsid != null) {
        description = "Watch Ceph FSID directory for permission changes";
        wantedBy = [ "multi-user.target" ];
        pathConfig = {
          PathChanged = "/var/lib/ceph/${cfg.bootstrap.fsid}";
          Unit = "ceph-fsid-perms.service";
        };
      };

      systemd.tmpfiles.rules = [
        "d /bin 0755 root root -"
        "L+ /bin/bash - - - - ${pkgs.bashInteractive}/bin/bash"
        "L+ /bin/rm - - - - ${pkgs.coreutils}/bin/rm"
        "d /etc/ceph 0755 root root -"
        "d /etc/logrotate.d 0755 root root -"
        "d /var/lib/ceph 0755 ceph ceph -"
        "d /var/lib/ceph/mon 0755 ceph ceph -"
        "d /var/lib/ceph/mgr 0755 ceph ceph -"
        "d /var/log/ceph 0755 ceph ceph -"
      ]
      ++ lib.optionals cfg.enable [
        "d /run/ceph 0755 ceph ceph -"
      ]
      ++ lib.optionals (cfg.bootstrap.fsid != null) [
        "d /var/lib/ceph/${cfg.bootstrap.fsid} 0755 ceph ceph -"
      ];

      # Ship upstream ceph-* unit templates (mon/mgr/osd) so ExecStart is present.
      systemd.packages = lib.mkIf cfg.enable [ cephPkg ];
      systemd.services."ceph-osd@" = {
        path = [
          pkgs.coreutils
          pkgs.iproute2
          pkgs.util-linux
        ];
      };
      # Ensure /run/ceph exists and is writable by the ceph user before mon starts.
      systemd.services."ceph-mon@" = {
        unitConfig.ConditionPathExists = "/etc/ceph/ceph.conf";
        serviceConfig = {
          ExecStart = lib.mkForce [
            ""
            "${cephPkg}/bin/ceph-mon -f --id %i --setuser ceph --setgroup ceph"
          ];
          ExecStartPre = [
            "${pkgs.coreutils}/bin/mkdir -p /run/ceph"
            "${pkgs.coreutils}/bin/chown ceph:ceph /run/ceph"
          ]
          ++ lib.optionals (cfg.bootstrap.fsid != null) [
            (pkgs.writeShellScript "ceph-mon-prepare-paths" ''
              set -euo pipefail
              fsid=${lib.escapeShellArg cfg.bootstrap.fsid}
              host=${lib.escapeShellArg hostName}
              install -d -m0755 -o ceph -g ceph /var/lib/ceph/mon "/var/lib/ceph/''${fsid}"
              mon_src="/var/lib/ceph/''${fsid}/mon.''${host}"
              mon_link="/var/lib/ceph/mon/ceph-''${host}"
              fs_root="/var/lib/ceph/''${fsid}"
              if [ -d "''${mon_src}" ] && [ ! -e "''${mon_link}" ]; then
                ln -s "''${mon_src}" "''${mon_link}"
              fi
              chown -h ceph:ceph "''${mon_link}" "''${mon_src}" 2>/dev/null || true
              if [ -d "''${fs_root}" ]; then
                chown ceph:ceph "''${fs_root}" || true
                chmod 0755 "''${fs_root}" || true
              fi
              if [ -d "''${mon_src}" ]; then
                chown -R ceph:ceph "''${mon_src}" || true
                if [ -f "''${mon_src}/keyring" ]; then
                  chmod 0600 "''${mon_src}/keyring" || true
                fi
              fi
            '')
          ];
        };
      };
      # Ensure manager state directory exists and is writable.
      systemd.services."ceph-mgr@" = {
        unitConfig.ConditionPathExists = "/etc/ceph/ceph.conf";
        environment = {
          PYTHONPATH = "${pythonWithCephadmDeps}/${pythonSite}";
        };
        serviceConfig = {
          ExecStart = lib.mkForce [
            ""
            "${cephPkg}/bin/ceph-mgr -f --id %i --setuser ceph --setgroup ceph"
          ];
          ExecStartPre = [
            (pkgs.writeShellScript "ceph-mgr-prepare-paths" ''
              set -euo pipefail
              host=${lib.escapeShellArg hostName}
              install -d -m0755 -o ceph -g ceph /var/lib/ceph/mgr "/var/lib/ceph/mgr/ceph-''${host}"
            '')
          ];
        };
      };

      # Ensure libvirt RBD pools are present and active when kvm role is enabled.
      systemd.services.libvirt-ceph-pools =
        lib.mkIf (config.virtualisation.libvirtd.enable && cfg.kvm.enable or false)
          {
            description = "Ensure Ceph RBD pools are active";
            after = [ "libvirtd.service" ];
            wants = [ "libvirtd.service" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = pkgs.writeShellScript "libvirt-ceph-pools-start" ''
                set -euo pipefail
                ${pkgs.libvirt}/bin/virsh pool-start ceph-images || true
                ${pkgs.libvirt}/bin/virsh pool-start ceph-vmdisks || true
              '';
              RemainAfterExit = true;
            };
            wantedBy = [ "multi-user.target" ];
          };
      # Only enable native mon/mgr instances when not using cephadm bootstrap.
      # Bootstrap hosts are managed via ceph-<fsid>@*.service units from cephadm.
      systemd.services."ceph-mon@${hostName}" = lib.mkIf (!cfg.bootstrap.enable) {
        enable = lib.mkDefault true;
        wantedBy = lib.mkDefault [ "multi-user.target" ];
        after = [
          "network-online.target"
          "ceph-user-sync.service"
        ];
        wants = [
          "network-online.target"
          "ceph-user-sync.service"
        ];
      };
      systemd.services."ceph-mgr@${hostName}" = lib.mkIf (!cfg.bootstrap.enable) {
        enable = lib.mkDefault true;
        wantedBy = lib.mkDefault [ "multi-user.target" ];
        after = [
          "network-online.target"
          "ceph-user-sync.service"
          "ceph-mon@${hostName}.service"
        ];
        wants = [
          "network-online.target"
          "ceph-user-sync.service"
          "ceph-mon@${hostName}.service"
        ];
      };

      networking.firewall = lib.mkIf cfg.openFirewall {
        allowedTCPPorts = [
          3300
          6789
        ]
        ++ lib.optionals cfg.rgw.enable [ cfg.rgw.port ]
        ++ lib.optionals (cfg.rgw.enable && cfg.rgw.sslPort != null) [ cfg.rgw.sslPort ];
        allowedTCPPortRanges = [
          {
            from = 6800;
            to = 7300;
          }
        ];
      };

      systemd.services.cephadm-bootstrap = lib.mkIf cfg.bootstrap.enable {
        description = "Cephadm bootstrap (single-host)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = rgwPath;
        unitConfig = {
          # Check for admin keyring instead of ceph.conf to allow client config to coexist
          ConditionPathExists = "!/etc/ceph/ceph.client.admin.keyring";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          BindPaths = [ "/run/systemd/system:/etc/static/systemd/system" ];
          ExecStart =
            let
              bootstrapArgs = lib.escapeShellArgs (
                [
                  "bootstrap"
                  "--mon-ip"
                  cfg.bootstrap.monIp
                  "--allow-fqdn-hostname"
                  "--allow-overwrite"
                ]
                ++ lib.optional (cfg.bootstrap.publicNetwork != null) "--skip-mon-network"
                ++ lib.optional cfg.bootstrap.singleHostDefaults "--single-host-defaults"
                ++ lib.optional cfg.bootstrap.skipDashboard "--skip-dashboard"
                ++ lib.optional (cfg.bootstrap.fsid != null) "--fsid"
                ++ lib.optional (cfg.bootstrap.fsid != null) cfg.bootstrap.fsid
                ++ lib.optional (cfg.bootstrap.clusterNetwork != null) "--cluster-network"
                ++ lib.optional (cfg.bootstrap.clusterNetwork != null) cfg.bootstrap.clusterNetwork
                ++ cfg.bootstrap.extraArgs
              );
              fsid = if cfg.bootstrap.fsid != null then cfg.bootstrap.fsid else "";
              zapDevicesFlag = lib.boolToString cfg.osd.zapDevices;
            in
            pkgs.writeShellScript "cephadm-bootstrap" ''
              set -euo pipefail

              # cephadm must manage persistent systemd units during bootstrap.
              # Use real systemctl here (not the runtime shim from cephadmPath).
              export PATH="${
                lib.makeBinPath (
                  with pkgs;
                  [
                    systemd
                    bash
                    coreutils
                    cryptsetup
                    findutils
                    gawk
                    gptfdisk
                    gnugrep
                    gnused
                    iproute2
                    iputils
                    jq
                    lvm2
                    parted
                    podman
                    util-linux
                  ]
                )
              }"

              # cephadm expects mutable systemd unit state on NixOS where /etc/systemd/system
              # is immutable and runtime units may already exist. Use a tolerant wrapper only
              # for this bootstrap flow.
              bootstrap_bin_dir="$(mktemp -d)"
              cat >"''${bootstrap_bin_dir}/systemctl" <<'EOF'
              #!/usr/bin/env bash
              set -euo pipefail

              cmd="''${1:-}"
              if [ -z "$cmd" ]; then
                exec ${pkgs.systemd}/bin/systemctl
              fi
              shift

              if [ "$cmd" = "enable" ] || [ "$cmd" = "reenable" ] || [ "$cmd" = "disable" ]; then
                err_file="$(mktemp)"
                if ${pkgs.systemd}/bin/systemctl --runtime "$cmd" "$@" 2>"$err_file"; then
                  rm -f "$err_file"
                  exit 0
                fi
                if grep -q "File '/run/systemd/system/ceph.target' already exists" "$err_file" || grep -q "Read-only file system" "$err_file"; then
                  echo "cephadm-bootstrap: ignoring systemctl $cmd error: $(cat "$err_file")" >&2
                  rm -f "$err_file"
                  exit 0
                fi
                cat "$err_file" >&2
                rm -f "$err_file"
                exit 1
              fi

              exec ${pkgs.systemd}/bin/systemctl "$cmd" "$@"
              EOF
              chmod 0755 "''${bootstrap_bin_dir}/systemctl"
              export PATH="''${bootstrap_bin_dir}:$PATH"

              # Clean stale runtime ceph target links left behind by previous attempts.
              rm -f /run/systemd/system/ceph.target
              rm -rf /run/systemd/system/ceph.target.wants

              run_cephadm() {
                ${cephPkg}/bin/cephadm ${lib.escapeShellArgs cephadmArgs} "$@"
              }

              run_bootstrap() {
                run_cephadm ${bootstrapArgs}
              }

              cleanup_stale_state() {
                if [ -z "${fsid}" ]; then
                  return 0
                fi

                echo "cephadm-bootstrap: cleaning stale state for fsid ${fsid}" >&2
                ${pkgs.systemd}/bin/systemctl stop "ceph.target" "ceph-mon@${hostName}.service" "ceph-mgr@${hostName}.service" >/dev/null 2>&1 || true
                run_cephadm rm-cluster --force --fsid "${fsid}" >/dev/null 2>&1 || true
                if [ "${zapDevicesFlag}" = "true" ]; then
                  run_cephadm rm-cluster --force --zap-osds --fsid "${fsid}" >/dev/null 2>&1 || true
                fi
                rm -f /run/systemd/system/ceph.target
                rm -rf /run/systemd/system/ceph.target.wants
                rm -rf -- "/var/lib/ceph/${fsid}" "/var/lib/ceph/mon/ceph-${hostName}" "/var/lib/ceph/mgr/ceph-${hostName}"
                rm -f /etc/ceph/ceph.conf /etc/ceph/ceph.client.admin.keyring
              }

              retry_bootstrap_from_clean_state() {
                cleanup_stale_state
                run_bootstrap 2> >(tee "$bootstrap_err" >&2)
              }

              bootstrap_err="$(mktemp)"
              if run_bootstrap 2> >(tee "$bootstrap_err" >&2); then
                rm -f "$bootstrap_err"
                exit 0
              fi

              if [ -n "${fsid}" ] && grep -q "same fsid '${fsid}' already exists" "$bootstrap_err"; then
                if run_cephadm ls | jq -e --arg fsid "${fsid}" '.[] | select(.fsid == $fsid)' >/dev/null 2>&1; then
                  echo "cephadm-bootstrap: cluster fsid ${fsid} already exists; treating bootstrap as converged" >&2
                  if [ ! -s /etc/ceph/ceph.client.admin.keyring ]; then
                    echo "cephadm-bootstrap: admin keyring missing, attempting recovery from existing cluster" >&2
                    if timeout 45 run_cephadm shell --fsid "${fsid}" -- ceph auth get client.admin -o /etc/ceph/ceph.client.admin.keyring >/dev/null 2>&1; then
                      chmod 0600 /etc/ceph/ceph.client.admin.keyring || true
                    else
                      echo "cephadm-bootstrap: unable to recover admin keyring from cluster ${fsid}; retrying bootstrap from clean state" >&2
                      if retry_bootstrap_from_clean_state; then
                        rm -f "$bootstrap_err"
                        exit 0
                      fi
                      rm -f "$bootstrap_err"
                      exit 1
                    fi
                  fi
                  rm -f "$bootstrap_err"
                  exit 0
                fi

                stale_root="/var/lib/ceph/${fsid}"
                echo "cephadm-bootstrap: stale fsid marker for ${fsid}; cleaning state and retrying bootstrap" >&2
                rm -rf -- "$stale_root"
                retry_bootstrap_from_clean_state
                rm -f "$bootstrap_err"
                exit 0
              fi

              if [ "${zapDevicesFlag}" = "true" ] && [ -n "${fsid}" ] && [ ! -s /etc/ceph/ceph.client.admin.keyring ]; then
                stale_root="/var/lib/ceph/${fsid}"
                if [ -d "$stale_root" ]; then
                  echo "cephadm-bootstrap: detected stale fsid state at $stale_root; cleaning and retrying once" >&2
                  rm -rf -- "$stale_root"
                  retry_bootstrap_from_clean_state
                  rm -f "$bootstrap_err"
                  exit 0
                fi
              fi

              rm -f "$bootstrap_err"
              exit 1
            '';
        };
      };

      systemd.services.cephadm-public-network = lib.mkIf (cfg.bootstrap.publicNetwork != null) {
        description = "Cephadm public network configuration";
        after = [ "cephadm-bootstrap.service" ];
        wants = [ "cephadm-bootstrap.service" ];
        wantedBy = [ "multi-user.target" ];
        path = cephadmPath;
        unitConfig = {
          ConditionPathExists = "/etc/ceph/ceph.conf";
          StartLimitIntervalSec = 0;
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart =
            let
              inherit (cfg.bootstrap) publicNetwork;
              targetAddr =
                if cfg.monUpdate.address != null then
                  cfg.monUpdate.address
                else if cfg.bootstrap.monIp != null then
                  cfg.bootstrap.monIp
                else
                  "";
              legacyAddr = if cfg.monUpdate.legacyAddress != null then cfg.monUpdate.legacyAddress else "";
              inherit (cfg.monUpdate) v2Port;
            in
            pkgs.writeShellScript "cephadm-public-network" ''
              set -euo pipefail
              fsid=""
              if [ -f /etc/ceph/ceph.conf ]; then
                fsid="$(awk '/^[[:space:]]*fsid[[:space:]]*=/{print $3; exit}' /etc/ceph/ceph.conf || true)"
              fi

              keyring="/etc/ceph/ceph.client.admin.keyring"
              if [ ! -s "$keyring" ]; then
                echo "ceph public network: missing admin keyring at $keyring" >&2
                exit 1
              fi
              ceph_bin="${cephPkg}/bin/ceph"
              format_addrs() {
                local host="$1"
                case "$host" in
                  (*[!0-9.:]*)
                    printf 'v2:%s:%s' "$host" "${toString v2Port}"
                    ;;
                  (*)
                    printf 'v2:%s:%s' "$host" "${toString v2Port}"
                    ;;
                esac
              }

              connect_addrs=""
              for addr in ${targetAddr} ${legacyAddr}; do
                if [ -z "$addr" ]; then
                  continue
                fi
                candidate_addrs="$(format_addrs "$addr")"
                if timeout 10 "$ceph_bin" -m "$candidate_addrs" -n client.admin -k "$keyring" status >/dev/null 2>&1; then
                  connect_addrs="$candidate_addrs"
                  break
                fi
              done

              if [ -z "$connect_addrs" ]; then
                echo "ceph public network: unable to connect to mon for config update; skipping" >&2
                exit 0
              fi

              "$ceph_bin" -m "$connect_addrs" -n client.admin -k "$keyring" \
                config set mon public_network ${publicNetwork}
            '';
        };
      };

      systemd.services.cephadm-osd =
        lib.mkIf (cfg.osd.autoProvision && cfg.osd.provisioner == "cephadm")
          {
            description = "Cephadm OSD provisioning";
            after = [
              "network-online.target"
              "cephadm-cephadm-path.service"
              "cephadm-bootstrap.service"
            ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            path = cephadmPath;
            unitConfig.ConditionPathExists = "/etc/ceph/ceph.conf";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart =
                let
                  methodFlag = cfg.osd.method;
                  dmcryptFlag = lib.optionalString cfg.osd.encrypted "--dmcrypt";
                  zapDevicesFlag = lib.boolToString cfg.osd.zapDevices;
                  deviceList = lib.concatStringsSep " " cfg.osd.devices;
                  monCandidates =
                    let
                      rawCandidates = [
                        cfg.monUpdate.address
                        cfg.bootstrap.monIp
                      ]
                      ++ cfg.monHosts;
                    in
                    lib.concatStringsSep " " (lib.filter (host: host != null && host != "") rawCandidates);
                  inherit (cfg.monUpdate) v2Port;
                in
                pkgs.writeShellScript "cephadm-osd-provision" ''
                              set -euo pipefail
                              if [ -z "${deviceList}" ]; then
                                echo "No OSD devices configured, skipping." >&2
                                exit 0
                              fi

                              keyring="/etc/ceph/ceph.client.admin.keyring"
                              ceph_bin="${cephPkg}/bin/ceph"
                              connect_addrs=""
                              format_addrs() {
                                local host="$1"
                                case "$host" in
                                  (*[!0-9.:]*)
                                    printf 'v2:%s:%s' "$host" "${toString v2Port}"
                                    ;;
                                  (*)
                                    printf 'v2:%s:%s' "$host" "${toString v2Port}"
                                    ;;
                                esac
                              }
                              if [ -s "$keyring" ]; then
                                for addr in ${monCandidates}; do
                                  if [ -z "$addr" ]; then
                                    continue
                                  fi
                                  candidate_addrs="$(format_addrs "$addr")"
                                  if timeout 10 "$ceph_bin" -m "$candidate_addrs" -n client.admin -k "$keyring" status >/dev/null 2>&1; then
                                    connect_addrs="$candidate_addrs"
                                    break
                                  fi
                                done
                              fi

                              ceph_cmd() {
                                if [ -n "$connect_addrs" ] && [ -s "$keyring" ]; then
                                  "$ceph_bin" -m "$connect_addrs" -n client.admin -k "$keyring" "$@"
                                else
                                  ${cephadm} shell -- ceph "$@"
                                fi
                              }

                              add_osd() {
                                local dev="$1"
                                if [ -n "${dmcryptFlag}" ]; then
                                  if ceph_cmd orch daemon add osd "${osdHost}:$dev" ${methodFlag} ${dmcryptFlag}; then
                                    return 0
                                  fi
                                  echo "OSD add with dmcrypt failed, retrying without." >&2
                                fi
                                ceph_cmd orch daemon add osd "${osdHost}:$dev" ${methodFlag} || true
                              }

                              for _ in $(seq 1 30); do
                                if ceph_cmd status >/dev/null 2>&1; then
                                  break
                                fi
                                sleep 2
                              done

                              ceph_cmd config set mgr cephadm_path "${
                                if cfg.bootstrap.enable then cephadmMgrPathContainer else cephadmMgrPathHost
                              }" >/dev/null 2>&1 || true

                              resolved_devices=""
                              for dev in ${deviceList}; do
                                resolved="$(realpath -e "$dev" 2>/dev/null || true)"
                                if [ -z "$resolved" ]; then
                                  echo "Device path '$dev' not found on host, skipping." >&2
                                  continue
                                fi
                                resolved_devices="$resolved_devices $resolved"
                              done

                              if [ -z "$resolved_devices" ]; then
                                echo "No valid OSD devices found, skipping." >&2
                                exit 0
                              fi

                              deviceList="$resolved_devices"

                              should_zap="false"
                              zap_marker="/var/lib/ceph/.osd-zap-cephadm.done"
                              zapped_any="false"
                              if [ "${zapDevicesFlag}" = "true" ]; then
                                if [ -f "$zap_marker" ]; then
                                  echo "zapDevices=true but marker exists ($zap_marker); skipping destructive zap." >&2
                                else
                                  should_zap="true"
                                fi
                              fi

                              if [ "$should_zap" = "true" ]; then
                                for dev in $deviceList; do
                                  wipefs --all --force "$dev" || true
                                  sgdisk --zap-all "$dev" || true
                                  partprobe "$dev" || true
                                  ceph_cmd orch device zap "${osdHost}" "$dev" --force || true
                                  zapped_any="true"
                                done
                                if [ "$zapped_any" = "true" ]; then
                                  install -d -m 0755 /var/lib/ceph
                                  : > "$zap_marker"
                                fi
                              fi

                              devices_json="$(ceph_cmd orch device ls --format json 2>/dev/null || true)"
                              if [ -z "$devices_json" ]; then
                                echo "Device list unavailable, attempting direct OSD adds." >&2
                                for dev in $deviceList; do
                                  add_osd "$dev"
                                done
                                exit 0
                              fi

                              host_devices="$(
                                printf '%s' "$devices_json" | ${python} - "${osdHost}" <<'PY' || true
                  import json, sys
                  host = sys.argv[1]
                  try:
                      data = json.load(sys.stdin)
                  except json.JSONDecodeError:
                      sys.exit(2)
                  devices = []
                  for entry in data:
                      if entry.get("name") == host or entry.get("addr") == host:
                          devices.extend(entry.get("devices", []))
                  print(len(devices))
                  PY
                              )"

                              if [ -z "$host_devices" ]; then
                                host_devices=0
                              fi

                              if [ "$host_devices" -eq 0 ]; then
                                echo "No devices reported by cephadm, attempting direct OSD adds." >&2
                                for dev in $deviceList; do
                                  add_osd "$dev"
                                done
                                exit 0
                              fi

                              for dev in $deviceList; do
                                if printf '%s' "$devices_json" | ${python} - "$dev" <<'PY'
                  import json, sys
                  dev = sys.argv[1]
                  data = json.load(sys.stdin)
                  for host in data:
                      for d in host.get("devices", []):
                          if d.get("path") == dev:
                              sys.exit(0 if d.get("available") else 1)
                  sys.exit(2)
                  PY
                                then
                                  add_osd "$dev"
                                else
                                  echo "Skipping $dev (not available for OSD provisioning)" >&2
                                fi
                              done
                '';
            };
          };
      systemd.services.ceph-volume-osd-create =
        lib.mkIf (cfg.osd.autoProvision && cfg.osd.provisioner == "ceph-volume")
          {
            description = "Ceph OSD provisioning (ceph-volume)";
            before = [ "ceph-volume-osd-activate.service" ];
            after = [
              "network-online.target"
              "cephadm-bootstrap.service"
            ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            path = cephVolumePath;
            unitConfig.ConditionPathExists = "/etc/ceph/ceph.conf";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart =
                let
                  dmcryptFlag = lib.optionalString cfg.osd.encrypted "--dmcrypt";
                  zapDevicesFlag = lib.boolToString cfg.osd.zapDevices;
                  deviceList = lib.concatStringsSep " " cfg.osd.devices;
                  cephVolume = "${cephPkg}/bin/ceph-volume";
                  cephBin = "${cephPkg}/bin/ceph";
                  adminKeyring = "/etc/ceph/ceph.client.admin.keyring";
                  bootstrapKeyring = "/var/lib/ceph/bootstrap-osd/ceph.keyring";
                in
                pkgs.writeShellScript "ceph-volume-osd-create" ''
                  set -euo pipefail
                  if [ -z "${deviceList}" ]; then
                    echo "No OSD devices configured, skipping." >&2
                    exit 0
                  fi

                  if [ ! -s "${bootstrapKeyring}" ]; then
                    if [ ! -s "${adminKeyring}" ]; then
                      echo "Missing admin keyring at ${adminKeyring}, cannot create bootstrap OSD keyring." >&2
                      exit 1
                    fi
                    install -d -m 0755 /var/lib/ceph/bootstrap-osd
                    "${cephBin}" -n client.admin -k "${adminKeyring}" \
                      auth get-or-create client.bootstrap-osd mon 'allow profile bootstrap-osd' \
                      -o "${bootstrapKeyring}"
                    chmod 0600 "${bootstrapKeyring}"
                  fi

                  should_zap="false"
                  zap_marker="/var/lib/ceph/.osd-zap-ceph-volume.done"
                  zapped_any="false"
                  if [ "${zapDevicesFlag}" = "true" ]; then
                    if [ -f "$zap_marker" ]; then
                      echo "zapDevices=true but marker exists ($zap_marker); skipping destructive zap." >&2
                    else
                      should_zap="true"
                    fi
                  fi

                  if [ "$should_zap" = "true" ] && [ -s "${adminKeyring}" ]; then
                    fsid="$("${cephBin}" -n client.admin -k "${adminKeyring}" fsid 2>/dev/null || true)"
                    if [ -n "$fsid" ]; then
                      ${pkgs.systemd}/bin/systemctl list-units --type=service --no-legend "ceph-$fsid@osd.*" \
                        | ${pkgs.gawk}/bin/awk '{print $1}' \
                        | while read -r unit; do
                          if [ -n "$unit" ]; then
                            ${pkgs.systemd}/bin/systemctl stop "$unit" || true
                          fi
                        done
                    fi
                  fi

                  existing_json="$(${cephVolume} lvm list --format json 2>/dev/null || true)"
                  existing_devices="$(
                    printf '%s' "$existing_json" | ${python} - <<'PY' || true
                  import json, sys
                  try:
                      data = json.load(sys.stdin)
                  except json.JSONDecodeError:
                      sys.exit(1)
                  devices = set()
                  for osd in data.values():
                      for entry in osd:
                          for dev in entry.get("devices", []):
                              devices.add(dev)
                  print(" ".join(sorted(devices)))
                  PY
                  )"

                  for dev in ${deviceList}; do
                    resolved="$(realpath -e "$dev" 2>/dev/null || true)"
                    if [ -z "$resolved" ]; then
                      echo "Device path '$dev' not found on host, skipping." >&2
                      continue
                    fi
                    if printf '%s' "$existing_devices" | ${pkgs.gnugrep}/bin/grep -Fqx "$resolved"; then
                      echo "OSD already present on $resolved, skipping."
                      continue
                    fi
                    if [ "$should_zap" = "true" ]; then
                      ${cephVolume} lvm zap --destroy "$resolved" || true
                      ${cephVolume} raw zap --destroy "$resolved" || true
                      wipefs --all --force "$resolved" || true
                      sgdisk --zap-all "$resolved" || true
                      partprobe "$resolved" || true
                      blockdev --flushbufs "$resolved" || true
                      udevadm settle --timeout=10 || true
                      zapped_any="true"
                    fi
                    ${cephVolume} lvm create --data "$resolved" --no-systemd ${dmcryptFlag}
                  done

                  if [ "$should_zap" = "true" ] && [ "$zapped_any" = "true" ]; then
                    install -d -m 0755 /var/lib/ceph
                    : > "$zap_marker"
                  fi
                '';
            };
          };

      systemd.services.ceph-volume-osd-activate = lib.mkIf (cfg.osd.provisioner == "ceph-volume") {
        description = "Ceph OSD activation (ceph-volume)";
        after = [
          "network-online.target"
          "cephadm-runtime-daemons.service"
          "cephadm-bootstrap.service"
        ]
        ++ lib.optional cfg.osd.autoProvision "ceph-volume-osd-create.service";
        wants = [
          "network-online.target"
          "cephadm-runtime-daemons.service"
        ]
        ++ lib.optional cfg.osd.autoProvision "ceph-volume-osd-create.service";
        wantedBy = [ "multi-user.target" ];
        path = cephVolumePath;
        unitConfig.ConditionPathExists = "/etc/ceph/ceph.conf";
        serviceConfig = {
          Type = "oneshot";
          KillMode = "none";
          TimeoutSec = 300;
          ExecStart = pkgs.writeShellScript "ceph-volume-osd-activate" ''
            set -euo pipefail
            admin_keyring="/etc/ceph/ceph.client.admin.keyring"
            ceph_bin="${cephPkg}/bin/ceph"
            osd_device_class="${if cfg.osd.deviceClass == null then "" else cfg.osd.deviceClass}"
            if [ -s "$admin_keyring" ]; then
              for osd_dir in /var/lib/ceph/osd/ceph-*; do
                if [ ! -d "$osd_dir" ]; then
                  continue
                fi
                fsid="$(cat "$osd_dir/fsid" 2>/dev/null || true)"
                if [ -z "$fsid" ]; then
                  continue
                fi
                lockbox_keyring="$osd_dir/lockbox.keyring"
                if [ ! -s "$lockbox_keyring" ]; then
                  if ! timeout 10 "$ceph_bin" -n client.admin -k "$admin_keyring" \
                    auth get "client.osd-lockbox.$fsid" -o "$lockbox_keyring"; then
                    if ! timeout 10 "$ceph_bin" -n client.admin -k "$admin_keyring" \
                      auth get-or-create "client.osd-lockbox.$fsid" \
                      mon 'allow profile osd-lockbox' \
                      -o "$lockbox_keyring"; then
                      echo "ceph-volume: unable to refresh lockbox key for $fsid" >&2
                      continue
                    fi
                  fi
                  chown ceph:ceph "$lockbox_keyring" || true
                  chmod 0600 "$lockbox_keyring" || true
                fi
                timeout 10 "$ceph_bin" -n client.admin -k "$admin_keyring" \
                  auth caps "client.osd-lockbox.$fsid" \
                  mon 'allow profile osd-lockbox, allow command "config-key get"' \
                  >/dev/null 2>&1 || true
              done
            fi
            if ! timeout 300 ${cephPkg}/bin/ceph-volume lvm activate --all --no-systemd; then
              echo "ceph-volume activation failed; keeping system activation healthy" >&2
              exit 0
            fi

            for osd_dir in /var/lib/ceph/osd/ceph-*; do
              if [ ! -d "$osd_dir" ]; then
                continue
              fi
              osd_id="''${osd_dir##*/ceph-}"
              osd_keyring="$osd_dir/keyring"
              if [ -n "$osd_id" ]; then
                if [ ! -s "$osd_keyring" ]; then
                  echo "ceph-volume: skipping stale OSD dir $osd_dir (missing keyring)" >&2
                  ${pkgs.systemd}/bin/systemctl stop "ceph-osd@''${osd_id}.service" >/dev/null 2>&1 || true
                  ${pkgs.systemd}/bin/systemctl disable "ceph-osd@''${osd_id}.service" >/dev/null 2>&1 || true
                  ${pkgs.systemd}/bin/systemctl reset-failed "ceph-osd@''${osd_id}.service" >/dev/null 2>&1 || true
                  continue
                fi
                ${pkgs.systemd}/bin/systemctl start "ceph-osd@''${osd_id}.service" || true
                if [ -n "$osd_device_class" ] && [ -s "$admin_keyring" ]; then
                  timeout 10 "$ceph_bin" -n client.admin -k "$admin_keyring" \
                    osd crush rm-device-class "osd.''${osd_id}" >/dev/null 2>&1 || true
                  timeout 10 "$ceph_bin" -n client.admin -k "$admin_keyring" \
                    osd crush set-device-class "$osd_device_class" "osd.''${osd_id}" >/dev/null 2>&1 || true
                fi
              fi
            done
          '';
        };
      };

      # SOPS secrets for Ceph (backup key + lockbox keys)
      sops.secrets = lib.mkMerge (
        # Backup encryption key
        lib.optional (cfg.backup.enable && cfg.backup.secretKeyFile != null) {
          "ceph-backup-key" = {
            sopsFile = resolveSecret cfg.backup.secretKeyFile;
            format = "binary";
            mode = "0400";
            owner = "root";
          };
        }
        ++
          # OSD lockbox keys
          map (entry: {
            "${entry.secretName}" = {
              sopsFile = resolveSecret entry.secretKeyFile;
              format = "binary";
              mode = "0400";
              owner = "ceph";
              group = "ceph";
            };
          }) lockboxEntries
        ++ lib.optionals cfg.rgw.enable (
          map (entry: {
            "${entry.name}" = {
              sopsFile = resolveSecret entry.file;
              format = "binary";
              mode = "0400";
              owner = "root";
            };
          }) (lib.filter (entry: entry.file != null) rgwSecretEntries)
        )
      );

      # Service to import lockbox keys before OSD activation
      systemd.services.ceph-lockbox-import = lib.mkIf (lockboxEntries != [ ]) {
        description = "Import Ceph OSD lockbox keys from SOPS secrets";
        before = [ "ceph-volume-osd-activate.service" ];
        after = [ "cephadm-bootstrap.service" ];
        wantedBy = [ "multi-user.target" ];
        unitConfig.ConditionPathExists = "/etc/ceph/ceph.conf";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [
          pkgs.coreutils
          cephPkg
        ];
        script =
          let
            importCommands = lib.concatMapStringsSep "\n" (entry: ''
              # Import lockbox key for ${entry.name}
              device="${entry.device}"
              secret_path="${config.sops.secrets."${entry.secretName}".path}"
              if [ -e "$device" ] && [ -f "$secret_path" ]; then
                # Find the OSD directory for this device
                for osd_dir in /var/lib/ceph/osd/ceph-*; do
                  if [ ! -d "$osd_dir" ]; then
                    continue
                  fi
                  # Check if this OSD uses the device (via block symlink or lvm)
                  block_link="$osd_dir/block"
                  if [ -L "$block_link" ]; then
                    block_target="$(readlink -f "$block_link" 2>/dev/null || true)"
                    device_resolved="$(readlink -f "$device" 2>/dev/null || true)"
                    if [ "$block_target" = "$device_resolved" ] || [[ "$block_target" == *"$(basename "$device")"* ]]; then
                      lockbox_dir="$osd_dir"
                      lockbox_keyring="$lockbox_dir/lockbox.keyring"
                      echo "Importing lockbox key for $device -> $lockbox_keyring"
                      if [ ! -f "$lockbox_keyring" ] || [ ! -s "$lockbox_keyring" ]; then
                        cp "$secret_path" "$lockbox_keyring"
                        chown ceph:ceph "$lockbox_keyring"
                        chmod 0600 "$lockbox_keyring"
                        echo "Imported lockbox key to $lockbox_keyring"
                      else
                        echo "Lockbox keyring already exists at $lockbox_keyring"
                      fi
                      break
                    fi
                  fi
                done
              fi
            '') lockboxEntries;
          in
          ''
            set -euo pipefail
            ${importCommands}
          '';
      };

      systemd.services.ceph-key-backup = lib.mkIf cfg.backup.enable {
        description = "Ceph key backup (encrypted)";
        after = [
          "network-online.target"
          "cephadm-bootstrap.service"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
        };
        path = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnutar
          pkgs.gzip
          pkgs.openssl
          cephPkg
        ];
        script =
          let
            clusterId =
              if cfg.client.fsid != null && cfg.client.fsid != "" then
                cfg.client.fsid
              else if cfg.bootstrap.fsid != null && cfg.bootstrap.fsid != "" then
                cfg.bootstrap.fsid
              else
                config.networking.hostName;
            retention = toString cfg.backup.retentionDays;
          in
          ''
            set -euo pipefail
            umask 077
            backup_dir="${cfg.backup.destination}"
            secret_file="${config.sops.secrets."ceph-backup-key".path}"
            stamp="$(date -u +%Y%m%dT%H%M%SZ)"
            tmp_dir="$(mktemp -d)"
            tar_path="$tmp_dir/ceph-keys-${clusterId}-''${stamp}.tar.gz"
            enc_path="$backup_dir/ceph-keys-${clusterId}-''${stamp}.tar.gz.enc"

            install -d -m 0700 "$backup_dir"

            # Create a directory structure for the backup
            backup_staging="$tmp_dir/backup"
            mkdir -p "$backup_staging/etc/ceph"
            mkdir -p "$backup_staging/var/lib/ceph"
            mkdir -p "$backup_staging/config-key"

            # Copy keyring and config files
            find /etc/ceph -type f \( -name '*.keyring' -o -name '*.conf' \) -exec cp {} "$backup_staging/etc/ceph/" \; 2>/dev/null || true
            find /var/lib/ceph -type f -name '*.keyring' -exec sh -c 'dir=$(dirname "$1" | sed "s|^/var/lib/ceph|$2/var/lib/ceph|"); mkdir -p "$dir"; cp "$1" "$dir/"' _ {} "$backup_staging" \; 2>/dev/null || true

            # Export config-key data (includes dm-crypt secrets for encrypted OSDs)
            # This is critical for OSD recovery
            if ceph config-key dump > "$backup_staging/config-key/dump.json" 2>/dev/null; then
              echo "Exported config-key data"
            else
              echo "Warning: Could not export config-key data (cluster may not be available)" >&2
            fi

            # Export auth data for all clients
            if ceph auth export > "$backup_staging/config-key/auth-export.txt" 2>/dev/null; then
              echo "Exported auth data"
            else
              echo "Warning: Could not export auth data" >&2
            fi

            # Check if we have anything to backup
            file_count=$(find "$backup_staging" -type f | wc -l)
            if [ "$file_count" -eq 0 ]; then
              echo "No Ceph key material found; skipping backup." >&2
              rm -rf "$tmp_dir"
              exit 0
            fi

            # Create the tarball
            tar -czf "$tar_path" -C "$backup_staging" .
            openssl_bin="${pkgs.openssl}/bin/openssl"
            "$openssl_bin" enc -aes-256-ctr -pbkdf2 -salt -md sha256 \
              -pass "file:$secret_file" \
              -in "$tar_path" \
              -out "$enc_path"
            rm -rf "$tmp_dir"

            echo "Backup created: $enc_path"
            find "$backup_dir" -type f -name "ceph-keys-${clusterId}-*.tar.gz.enc" -mtime +${retention} -delete || true
          '';
      };

      systemd.timers.ceph-key-backup = lib.mkIf cfg.backup.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.backup.schedule;
          Persistent = true;
        };
      };

      # Health check service
      systemd.services.ceph-health-check = lib.mkIf cfg.healthCheck.enable {
        description = "Ceph cluster health check";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          RuntimeDirectory = "ceph";
          RuntimeDirectoryPreserve = "yes";
        };
        path = [
          pkgs.ceph
          pkgs.jq
          pkgs.coreutils
          pkgs.gawk
          pkgs.gnugrep
        ]
        ++ lib.optionals cfg.healthCheck.checkLibvirt [ pkgs.libvirt ];
        script =
          let
            warnExit = if cfg.healthCheck.warnIsFailure then "1" else "0";
            inherit (cfg.healthCheck) outputFile;
          in
          ''
            set -euo pipefail

            echo "=== Ceph Health Check $(date -Iseconds) ==="

            # Initialize status
            overall_status="OK"
            ceph_health=""
            ceph_status_json=""
            pool_status=""
            osd_status=""
            libvirt_status=""

            # Get Ceph health
            if ceph_health=$(ceph health 2>&1); then
              echo "Ceph Health: $ceph_health"
              case "$ceph_health" in
                HEALTH_OK*)
                  ;;
                HEALTH_WARN*)
                  ${lib.optionalString cfg.healthCheck.warnIsFailure ''overall_status="WARN"''}
                  ;;
                HEALTH_ERR*)
                  overall_status="ERROR"
                  ;;
              esac
            else
              echo "ERROR: Failed to get Ceph health: $ceph_health"
              overall_status="ERROR"
            fi

            # Get detailed status as JSON
            ceph_status_json=$(ceph status -f json 2>/dev/null || echo '{}')

            ${lib.optionalString cfg.healthCheck.checkPools ''
              # Check pools
              echo ""
              echo "=== Pool Status ==="
              if pool_status=$(ceph df -f json 2>&1); then
                echo "$pool_status" | jq -r '.pools[] | "Pool \(.name): \(.stats.stored // 0 | . / 1024 / 1024 | floor)MB stored, \(.stats.percent_used // 0 * 100 | . * 100 | floor / 100)% used"'
              else
                echo "ERROR: Failed to get pool status"
                overall_status="ERROR"
              fi
            ''}

            ${lib.optionalString cfg.healthCheck.checkOsds ''
              # Check OSDs
              echo ""
              echo "=== OSD Status ==="
              if osd_status=$(ceph osd stat 2>&1); then
                echo "$osd_status"
                # Check for down OSDs
                osd_tree=$(ceph osd tree -f json 2>/dev/null || echo '{}')
                down_osds=$(echo "$osd_tree" | jq -r '[.nodes[] | select(.type == "osd" and .status == "down")] | length')
                if [ "$down_osds" -gt 0 ]; then
                  echo "WARNING: $down_osds OSD(s) are down"
                  ${lib.optionalString cfg.healthCheck.warnIsFailure ''overall_status="WARN"''}
                fi
              else
                echo "ERROR: Failed to get OSD status"
                overall_status="ERROR"
              fi
            ''}

            ${lib.optionalString cfg.healthCheck.checkLibvirt (
              let
                poolsArg =
                  if cfg.healthCheck.libvirtPools == [ ] then
                    ""
                  else
                    lib.concatStringsSep " " cfg.healthCheck.libvirtPools;
              in
              ''
                # Check libvirt storage pools
                echo ""
                echo "=== Libvirt Storage Pools ==="
                if command -v virsh >/dev/null 2>&1; then
                  ${
                    if cfg.healthCheck.libvirtPools == [ ] then
                      "pools_to_check=$(virsh pool-list --name 2>/dev/null | grep -v '^$' || true)"
                    else
                      ''pools_to_check="${poolsArg}"''
                  }
                  for pool in $pools_to_check; do
                    if pool_info=$(virsh pool-info "$pool" 2>&1); then
                      state=$(echo "$pool_info" | grep "^State:" | awk '{print $2}' || echo "unknown")
                      capacity=$(echo "$pool_info" | grep "^Capacity:" | awk '{print $2, $3}' || echo "N/A")
                      available=$(echo "$pool_info" | grep "^Available:" | awk '{print $2, $3}' || echo "N/A")
                      if [ "$state" = "running" ]; then
                        echo "Pool $pool: $state (Capacity: $capacity, Available: $available)"
                      else
                        echo "Pool $pool: $state (inactive pools have no capacity info)"
                        echo "  WARNING: Pool $pool is not running"
                        # Always report WARN for inactive pools; exit code depends on warnIsFailure
                        if [ "$overall_status" = "OK" ]; then
                          overall_status="WARN"
                        fi
                      fi
                    else
                      echo "Pool $pool: ERROR - $pool_info"
                    fi
                  done
                else
                  echo "virsh not available"
                fi
              ''
            )}

            echo ""
            echo "=== Overall Status: $overall_status ==="

            ${lib.optionalString (outputFile != null) ''
                # Write JSON output
                cat > "${outputFile}" <<JSONEOF
              {
                "timestamp": "$(date -Iseconds)",
                "overall_status": "$overall_status",
                "ceph_health": "$ceph_health",
                "ceph_status": $ceph_status_json
              }
              JSONEOF
                chmod 644 "${outputFile}"
            ''}

            # Exit with appropriate code
            case "$overall_status" in
              OK)
                exit 0
                ;;
              WARN)
                exit ${warnExit}
                ;;
              ERROR)
                exit 1
                ;;
            esac
          '';
      };

      systemd.timers.ceph-health-check = lib.mkIf cfg.healthCheck.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.healthCheck.schedule;
          Persistent = true;
        };
      };

      # Run health check after NixOS activation (config changes)
      system.activationScripts.ceph-health-check =
        lib.mkIf (cfg.healthCheck.enable && cfg.healthCheck.runOnActivation)
          {
            text = ''
              # Schedule health check to run shortly after activation completes
              # Using systemd-run to avoid blocking activation
              if [ -f /etc/ceph/ceph.conf ]; then
                ${pkgs.systemd}/bin/systemd-run --no-block --unit=ceph-health-check-activation \
                  ${pkgs.systemd}/bin/systemctl start ceph-health-check.service || true
              fi
            '';
            deps = [ ];
          };

      systemd.services.cephadm-pools = lib.mkIf (allPools != [ ]) {
        description = "Ceph pool setup";
        after = [
          "network-online.target"
          "cephadm-runtime-daemons.service"
          "cephadm-cephadm-path.service"
          "cephadm-bootstrap.service"
        ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = cephadmPath;
        unitConfig.ConditionPathExists = "/etc/ceph/ceph.conf";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart =
            let
              poolEntries = allPools;
              allowPoolSizeOne = lib.any (pool: pool.size == 1) poolEntries;
              monCandidates =
                let
                  rawCandidates = [
                    cfg.monUpdate.address
                    cfg.bootstrap.monIp
                  ]
                  ++ cfg.monHosts;
                in
                lib.concatStringsSep " " (lib.filter (host: host != null && host != "") rawCandidates);
              inherit (cfg.monUpdate) v2Port;
            in
            pkgs.writeShellScript "cephadm-pools" ''
              set -euo pipefail
              keyring="/etc/ceph/ceph.client.admin.keyring"
              ceph_bin="${cephPkg}/bin/ceph"
              connect_addrs=""
              format_addrs() {
                local host="$1"
                case "$host" in
                  (*[!0-9.:]*)
                    printf 'v2:%s:%s' "$host" "${toString v2Port}"
                    ;;
                  (*)
                    printf 'v2:%s:%s' "$host" "${toString v2Port}"
                    ;;
                esac
              }
              if [ -s "$keyring" ]; then
                for addr in ${monCandidates}; do
                  if [ -z "$addr" ]; then
                    continue
                  fi
                  candidate_addrs="$(format_addrs "$addr")"
                  if timeout 10 "$ceph_bin" -m "$candidate_addrs" -n client.admin -k "$keyring" status >/dev/null 2>&1; then
                    connect_addrs="$candidate_addrs"
                    break
                  fi
                done
              fi

              ceph_cmd() {
                if [ -n "$connect_addrs" ] && [ -s "$keyring" ]; then
                  "$ceph_bin" -m "$connect_addrs" -n client.admin -k "$keyring" "$@"
                else
                  ${cephadm} shell -- ceph "$@"
                fi
              }

              ceph_cmd_timeout() {
                local timeout_secs="$1"
                shift
                if [ -n "$connect_addrs" ] && [ -s "$keyring" ]; then
                  timeout "$timeout_secs" "$ceph_bin" -m "$connect_addrs" -n client.admin -k "$keyring" "$@"
                else
                  timeout "$timeout_secs" ${cephadm} shell -- ceph "$@"
                fi
              }

              status_timeout=10
              status_attempts=10
              ready=0
              for _ in $(seq 1 "$status_attempts"); do
                if ceph_cmd_timeout "$status_timeout" status >/dev/null 2>&1; then
                  ready=1
                  break
                fi
                sleep 2
              done

              if [ "$ready" -ne 1 ]; then
                echo "cephadm-pools: cluster not reachable; skipping pool setup" >&2
                exit 0
              fi

              ${lib.optionalString allowPoolSizeOne ''
                ceph_cmd config set mon mon_allow_pool_size_one true || true
                ceph_cmd config set global mon_allow_pool_size_one true || true
                ceph_cmd config set mon mon_warn_on_pool_no_redundancy false || true
                ceph_cmd config set global mon_warn_on_pool_no_redundancy false || true
              ''}

              pools_json="$(ceph_cmd_timeout 20 osd pool ls --format json | sed -n '/^[[:space:]]*\\[/,$p' || true)"
              ${lib.concatStringsSep "\n" (
                map (pool: ''
                                if printf '%s' "$pools_json" | ${python} - "${pool.name}" <<'PY'
                  import json, sys
                  name = sys.argv[1]
                  try:
                      data = json.load(sys.stdin)
                  except json.JSONDecodeError:
                      sys.exit(1)
                  sys.exit(0 if name in data else 1)
                  PY
                                then
                                  :
                                else
                                  if [ -n "${lib.optionalString (pool.pgNum != null) (toString pool.pgNum)}" ]; then
                                    ceph_cmd osd pool create "${pool.name}" ${
                                      lib.optionalString (pool.pgNum != null) (toString pool.pgNum)
                                    }
                                  else
                                    ceph_cmd osd pool create "${pool.name}"
                                  fi
                                fi

                              ceph_cmd osd pool application enable "${pool.name}" "${pool.application}" >/dev/null 2>&1 || true
                              ${
                                if pool.size == 1 then
                                  ''
                                    ceph_cmd osd pool set "${pool.name}" size 1 --yes-i-really-mean-it
                                  ''
                                else
                                  ''
                                    ceph_cmd osd pool set "${pool.name}" size ${toString pool.size}
                                  ''
                              }
                                ${lib.optionalString (pool.minSize != null) ''
                                  ceph_cmd osd pool set "${pool.name}" min_size ${toString pool.minSize}
                                ''}
                '') poolEntries
              )}
            '';
        };
      };

      systemd.services.cephadm-cephfs = lib.mkIf (cfg.cephfs != [ ]) {
        description = "CephFS setup";
        after = [
          "network-online.target"
          "cephadm-runtime-daemons.service"
          "cephadm-cephadm-path.service"
          "cephadm-bootstrap.service"
          "cephadm-pools.service"
        ];
        wants = [
          "network-online.target"
          "cephadm-runtime-daemons.service"
          "cephadm-pools.service"
        ];
        wantedBy = [ "multi-user.target" ];
        path = cephadmPath;
        unitConfig.ConditionPathExists = "/etc/ceph/ceph.conf";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script =
          let
            monCandidates =
              let
                rawCandidates = [
                  cfg.monUpdate.address
                  cfg.bootstrap.monIp
                ]
                ++ cfg.monHosts;
              in
              lib.concatStringsSep " " (lib.filter (host: host != null && host != "") rawCandidates);
            inherit (cfg.monUpdate) v2Port;
            hasMds = lib.any (fs: fs.mds.enable) cfg.cephfs;
            fsCommands = lib.concatMapStringsSep "\n" (
              fs:
              let
                inherit (fs) dataPools;
                primaryDataPool = if dataPools == [ ] then null else builtins.head dataPools;
                extraDataPools = if dataPools == [ ] then [ ] else lib.drop 1 dataPools;
                primaryDataPoolName = if primaryDataPool == null then "" else primaryDataPool.name;
                extraDataPoolsList = lib.concatMapStringsSep " " (pool: pool.name) extraDataPools;
                metadataPoolName = fs.metadataPool.name;
                mdsEnabled = lib.boolToString fs.mds.enable;
                mdsCount = toString fs.mds.count;
                mdsStandby = if fs.mds.standbyCount == null then "" else toString fs.mds.standbyCount;
                mdsPlacement = if fs.mds.placement == null then "" else fs.mds.placement;
              in
              ''
                # CephFS ${fs.name}
                fs_name=${lib.escapeShellArg fs.name}
                metadata_pool=${lib.escapeShellArg metadataPoolName}
                primary_data_pool=${lib.escapeShellArg primaryDataPoolName}
                extra_data_pools=${lib.escapeShellArg extraDataPoolsList}
                mds_enable=${lib.escapeShellArg mdsEnabled}
                mds_count=${lib.escapeShellArg mdsCount}
                mds_standby=${lib.escapeShellArg mdsStandby}
                mds_placement=${lib.escapeShellArg mdsPlacement}

                if ! fs_exists "$fs_name"; then
                  if [ -z "$primary_data_pool" ]; then
                    echo "cephfs: $fs_name has no data pools configured" >&2
                    exit 1
                  fi
                  ceph_cmd fs new "$fs_name" "$metadata_pool" "$primary_data_pool"
                fi

                for pool in $extra_data_pools; do
                  if [ -n "$pool" ]; then
                    if ! ceph_cmd fs add_data_pool "$fs_name" "$pool"; then
                      echo "cephfs: add_data_pool $pool failed; continuing" >&2
                    fi
                  fi
                done

                if [ "$mds_enable" = "true" ]; then
                  if [ -n "$mds_count" ]; then
                    ceph_cmd fs set "$fs_name" max_mds "$mds_count" || true
                  fi
                  if [ -n "$mds_standby" ]; then
                    ceph_cmd fs set "$fs_name" standby_count_wanted "$mds_standby" || true
                  fi
                  placement_arg="$mds_placement"
                  if [ -z "$placement_arg" ]; then
                    placement_arg="$mds_count"
                  fi
                  if [ "$orchestrator_ready" -ne 1 ]; then
                    echo "cephfs: orchestrator unavailable; skipping MDS placement for $fs_name this run" >&2
                  elif [ -n "$placement_arg" ]; then
                    if ! ceph_cmd orch apply mds "$fs_name" --placement "$placement_arg"; then
                      echo "cephfs: unable to apply MDS placement for $fs_name; check cephadm/orchestrator health" >&2
                      exit 1
                    fi
                  fi
                fi
              ''
            ) cfg.cephfs;
          in
          ''
            set -euo pipefail
            keyring="/etc/ceph/ceph.client.admin.keyring"
            ceph_bin="${cephPkg}/bin/ceph"
            connect_addrs=""
            format_addrs() {
              local host="$1"
              case "$host" in
                (*[!0-9.:]*)
                  printf 'v2:%s:%s' "$host" "${toString v2Port}"
                  ;;
                (*)
                  printf 'v2:%s:%s' "$host" "${toString v2Port}"
                  ;;
              esac
            }
            if [ -s "$keyring" ]; then
              for addr in ${monCandidates}; do
                if [ -z "$addr" ]; then
                  continue
                fi
                candidate_addrs="$(format_addrs "$addr")"
                if timeout 10 "$ceph_bin" -m "$candidate_addrs" -n client.admin -k "$keyring" status >/dev/null 2>&1; then
                  connect_addrs="$candidate_addrs"
                  break
                fi
              done
            fi

            ceph_cmd() {
              if [ -n "$connect_addrs" ] && [ -s "$keyring" ]; then
                "$ceph_bin" -m "$connect_addrs" -n client.admin -k "$keyring" "$@"
              else
                ${cephadm} shell -- ceph "$@"
              fi
            }

            ceph_cmd_timeout() {
              local timeout_secs="$1"
              shift
              if [ -n "$connect_addrs" ] && [ -s "$keyring" ]; then
                timeout "$timeout_secs" "$ceph_bin" -m "$connect_addrs" -n client.admin -k "$keyring" "$@"
              else
                timeout "$timeout_secs" ${cephadm} shell -- ceph "$@"
              fi
            }

            status_timeout=10
            status_attempts=10
            ready=0
            for _ in $(seq 1 "$status_attempts"); do
              if ceph_cmd_timeout "$status_timeout" status >/dev/null 2>&1; then
                ready=1
                break
              fi
              sleep 2
            done

            if [ "$ready" -ne 1 ]; then
              echo "cephadm-cephfs: cluster not reachable; skipping filesystem setup" >&2
              exit 0
            fi

            fs_list_json="$(ceph_cmd_timeout 20 fs ls --format json 2>/dev/null || echo '[]')"
            fs_exists() {
              local name="$1"
              printf '%s' "$fs_list_json" | ${python} - "$name" <<'PY' || return 1
            import json, sys
            name = sys.argv[1]
            try:
                data = json.load(sys.stdin)
            except Exception:
                sys.exit(1)
            for entry in data:
                if entry.get("name") == name:
                    sys.exit(0)
            sys.exit(1)
            PY
            }

            orchestrator_ready=1
            if [ "${lib.boolToString hasMds}" = "true" ]; then
              if ! ceph_cmd_timeout 10 orch status >/dev/null 2>&1; then
                ceph_cmd mgr module enable cephadm >/dev/null 2>&1 || true
                ceph_cmd config set mgr mgr/orchestrator/orchestrator cephadm >/dev/null 2>&1 || true
              fi
              if ! ceph_cmd_timeout 10 orch status >/dev/null 2>&1; then
                echo "cephadm-cephfs: orchestrator commands unavailable; skipping MDS orchestration this run" >&2
                orchestrator_ready=0
              fi
            fi

            ${fsCommands}
          '';
      };

      systemd.services.cephadm-rgw = lib.mkIf cfg.rgw.enable {
        description = "Ceph RGW setup";
        after = [
          "network-online.target"
          "cephadm-runtime-daemons.service"
          "cephadm-cephadm-path.service"
          "cephadm-bootstrap.service"
          "cephadm-pools.service"
        ];
        wants = [
          "network-online.target"
          "cephadm-runtime-daemons.service"
          "cephadm-pools.service"
        ];
        wantedBy = [ "multi-user.target" ];
        path = cephadmPath;
        unitConfig.ConditionPathExists = "/etc/ceph/ceph.conf";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script =
          let
            monCandidates =
              let
                rawCandidates = [
                  cfg.monUpdate.address
                  cfg.bootstrap.monIp
                ]
                ++ cfg.monHosts;
              in
              lib.concatStringsSep " " (lib.filter (host: host != null && host != "") rawCandidates);
            inherit (cfg.monUpdate) v2Port;
            endpointArg = lib.optionalString (
              cfg.rgw.endpoint != null && cfg.rgw.endpoint != ""
            ) "--endpoints ${lib.escapeShellArg cfg.rgw.endpoint}";
            sslPortArg = lib.optionalString (cfg.rgw.sslPort != null) "--ssl-port ${toString cfg.rgw.sslPort}";
            zonegroupModifyCmd = lib.optionalString (cfg.rgw.endpoint != null && cfg.rgw.endpoint != "") ''
              rgw_admin zonegroup modify \
                --rgw-realm "$rgw_realm" \
                --rgw-zonegroup "$rgw_zonegroup" \
                ${endpointArg}
            '';
            zoneModifyCmd = lib.optionalString (cfg.rgw.endpoint != null && cfg.rgw.endpoint != "") ''
              rgw_admin zone modify \
                --rgw-realm "$rgw_realm" \
                --rgw-zonegroup "$rgw_zonegroup" \
                --rgw-zone "$rgw_zone" \
                ${endpointArg}
            '';
            userCommands = lib.concatMapStringsSep "\n" (
              user:
              let
                displayName =
                  if user.displayName != null && user.displayName != "" then user.displayName else user.name;
                accessFile = config.sops.secrets."${user.accessSecretName}".path;
                secretFile = config.sops.secrets."${user.secretSecretName}".path;
                capsValue = lib.concatStringsSep ";" user.caps;
              in
              ''
                                # RGW user ${user.name}
                                rgw_user=${lib.escapeShellArg user.name}
                                rgw_display=${lib.escapeShellArg displayName}
                                rgw_access_file=${lib.escapeShellArg accessFile}
                                rgw_secret_file=${lib.escapeShellArg secretFile}
                                rgw_caps=${lib.escapeShellArg capsValue}

                                if [ ! -s "$rgw_access_file" ] || [ ! -s "$rgw_secret_file" ]; then
                                  echo "cephadm-rgw: missing key material for $rgw_user" >&2
                                  exit 1
                                fi

                                rgw_access_key="$(tr -d '\n' < "$rgw_access_file")"
                                rgw_secret_key="$(tr -d '\n' < "$rgw_secret_file")"

                                user_info="$(rgw_admin_zone user info --uid "$rgw_user" --format json 2>/dev/null || true)"
                                if [ -z "$user_info" ]; then
                                  rgw_admin_zone user create \
                                    --uid "$rgw_user" \
                                    --display-name "$rgw_display" \
                                    --access-key "$rgw_access_key" \
                                    --secret-key "$rgw_secret_key"
                                else
                  read -r current_access current_secret < <(
                    printf '%s' "$user_info" | ${python} - <<'PY'
                import json, sys
                try:
                    data = json.load(sys.stdin)
                except Exception:
                    sys.exit(0)
                keys = data.get("keys", [])
                if keys:
                    access = keys[0].get("access_key", "")
                    secret = keys[0].get("secret_key", "")
                    print(f"{access} {secret}")
                PY
                  ) || true
                                  if [ "$current_access" != "$rgw_access_key" ] || [ "$current_secret" != "$rgw_secret_key" ]; then
                                    rgw_admin_zone user modify \
                                      --uid "$rgw_user" \
                                      --access-key "$rgw_access_key" \
                                      --secret-key "$rgw_secret_key"
                                  fi
                                fi

                                if [ -n "$rgw_caps" ]; then
                                  rgw_admin_zone caps add --uid "$rgw_user" --caps "$rgw_caps" || true
                                fi
              ''
            ) rgwUsers;
            bucketCommands = lib.concatMapStringsSep "\n" (
              bucket:
              let
                accessFile = config.sops.secrets."${bucket.ownerAccessSecretName}".path;
                secretFile = config.sops.secrets."${bucket.ownerSecretSecretName}".path;
              in
              ''
                # RGW bucket ${bucket.fullName}
                rgw_bucket=${lib.escapeShellArg bucket.fullName}
                rgw_bucket_owner=${lib.escapeShellArg bucket.user}
                rgw_bucket_access_file=${lib.escapeShellArg accessFile}
                rgw_bucket_secret_file=${lib.escapeShellArg secretFile}

                if [ -z "$rgw_endpoint" ]; then
                  echo "cephadm-rgw: endpoint not set; skipping bucket create for $rgw_bucket" >&2
                elif [ "$rgw_endpoint_ready" -ne 1 ]; then
                  echo "cephadm-rgw: endpoint not ready; deferring bucket create for $rgw_bucket" >&2
                elif [ ! -s "$rgw_bucket_access_file" ] || [ ! -s "$rgw_bucket_secret_file" ]; then
                  echo "cephadm-rgw: missing bucket credentials for $rgw_bucket_owner" >&2
                  exit 1
                else
                  rgw_bucket_access="$(tr -d '\n' < "$rgw_bucket_access_file")"
                  rgw_bucket_secret="$(tr -d '\n' < "$rgw_bucket_secret_file")"
                  if ! AWS_ACCESS_KEY_ID="$rgw_bucket_access" \
                    AWS_SECRET_ACCESS_KEY="$rgw_bucket_secret" \
                    AWS_EC2_METADATA_DISABLED=true \
                    AWS_DEFAULT_REGION="$rgw_region" \
                    AWS_S3_FORCE_PATH_STYLE=true \
                    ${pkgs.awscli2}/bin/aws --endpoint-url "$rgw_endpoint" s3api head-bucket --bucket "$rgw_bucket" \
                    >/dev/null 2>&1; then
                    create_args=()
                    if [ "$rgw_region" != "us-east-1" ]; then
                      create_args=(--create-bucket-configuration "LocationConstraint=$rgw_region")
                    fi
                    bucket_created=0
                    for _ in $(seq 1 5); do
                      if AWS_ACCESS_KEY_ID="$rgw_bucket_access" \
                        AWS_SECRET_ACCESS_KEY="$rgw_bucket_secret" \
                        AWS_EC2_METADATA_DISABLED=true \
                        AWS_DEFAULT_REGION="$rgw_region" \
                        AWS_S3_FORCE_PATH_STYLE=true \
                        ${pkgs.awscli2}/bin/aws --endpoint-url "$rgw_endpoint" s3api create-bucket \
                        --bucket "$rgw_bucket" "''${create_args[@]}" \
                        >/dev/null 2>&1; then
                        bucket_created=1
                        break
                      fi
                      sleep 2
                    done
                    if [ "$bucket_created" -ne 1 ]; then
                      echo "cephadm-rgw: failed to create bucket $rgw_bucket; will retry on next run" >&2
                    fi
                  fi
                fi
              ''
            ) rgwBucketEntries;
          in
          ''
            set -euo pipefail
            keyring="/etc/ceph/ceph.client.admin.keyring"
            ceph_bin="${cephPkg}/bin/ceph"
            radosgw_admin="${cephPkg}/bin/radosgw-admin"
            connect_addrs=""
            format_addrs() {
              local host="$1"
              case "$host" in
                (*[!0-9.:]*)
                  printf 'v2:%s:%s' "$host" "${toString v2Port}"
                  ;;
                (*)
                  printf 'v2:%s:%s' "$host" "${toString v2Port}"
                  ;;
              esac
            }
            if [ -s "$keyring" ]; then
              for addr in ${monCandidates}; do
                if [ -z "$addr" ]; then
                  continue
                fi
                candidate_addrs="$(format_addrs "$addr")"
                if timeout 10 "$ceph_bin" -m "$candidate_addrs" -n client.admin -k "$keyring" status >/dev/null 2>&1; then
                  connect_addrs="$candidate_addrs"
                  break
                fi
              done
            fi

            ceph_cmd() {
              if [ -n "$connect_addrs" ] && [ -s "$keyring" ]; then
                "$ceph_bin" -m "$connect_addrs" -n client.admin -k "$keyring" "$@"
              else
                ${cephadm} shell -- ceph "$@"
              fi
            }

            ceph_cmd_timeout() {
              local timeout_secs="$1"
              shift
              if [ -n "$connect_addrs" ] && [ -s "$keyring" ]; then
                timeout "$timeout_secs" "$ceph_bin" -m "$connect_addrs" -n client.admin -k "$keyring" "$@"
              else
                timeout "$timeout_secs" ${cephadm} shell -- ceph "$@"
              fi
            }

            rgw_admin() {
              if [ -n "$connect_addrs" ] && [ -s "$keyring" ]; then
                "$radosgw_admin" -n client.admin -k "$keyring" "$@"
              else
                ${cephadm} shell -- radosgw-admin -n client.admin -k "$keyring" "$@"
              fi
            }
            rgw_admin_zone() {
              rgw_admin \
                --rgw-realm "$rgw_realm" \
                --rgw-zonegroup "$rgw_zonegroup" \
                --rgw-zone "$rgw_zone" \
                "$@"
            }

            status_timeout=10
            status_attempts=10
            ready=0
            for _ in $(seq 1 "$status_attempts"); do
              if ceph_cmd_timeout "$status_timeout" status >/dev/null 2>&1; then
                ready=1
                break
              fi
              sleep 2
            done

            if [ "$ready" -ne 1 ]; then
              echo "cephadm-rgw: cluster not reachable; skipping rgw setup" >&2
              exit 0
            fi

            if ! ceph_cmd_timeout 10 orch status >/dev/null 2>&1; then
              ceph_cmd mgr module enable cephadm >/dev/null 2>&1 || true
              ceph_cmd config set mgr mgr/orchestrator/orchestrator cephadm >/dev/null 2>&1 || true
            fi
            if ! ceph_cmd_timeout 10 orch status >/dev/null 2>&1; then
              echo "cephadm-rgw: orchestrator commands unavailable; check cephadm_path permissions" >&2
              exit 1
            fi

            rgw_realm=${lib.escapeShellArg cfg.rgw.realm}
            rgw_zonegroup=${lib.escapeShellArg cfg.rgw.zonegroup}
            rgw_zone=${lib.escapeShellArg cfg.rgw.zone}
            rgw_service=${lib.escapeShellArg cfg.rgw.serviceId}
            rgw_placement=${lib.escapeShellArg cfg.rgw.placement}
            rgw_port=${lib.escapeShellArg (toString cfg.rgw.port)}
            rgw_endpoint=${lib.escapeShellArg (if cfg.rgw.endpoint != null then cfg.rgw.endpoint else "")}
            rgw_region=${lib.escapeShellArg cfg.rgw.region}

            if ! rgw_admin realm get --rgw-realm "$rgw_realm" >/dev/null 2>&1; then
              rgw_admin realm create --rgw-realm "$rgw_realm" --default
            fi

            if ! rgw_admin zonegroup get --rgw-realm "$rgw_realm" --rgw-zonegroup "$rgw_zonegroup" >/dev/null 2>&1; then
              rgw_admin zonegroup create \
                --rgw-realm "$rgw_realm" \
                --rgw-zonegroup "$rgw_zonegroup" \
                --master \
                --default ${endpointArg}
            else
              ${zonegroupModifyCmd}
            fi

            if ! rgw_admin zone get --rgw-realm "$rgw_realm" --rgw-zonegroup "$rgw_zonegroup" --rgw-zone "$rgw_zone" \
              >/dev/null 2>&1; then
              rgw_admin zone create \
                --rgw-realm "$rgw_realm" \
                --rgw-zonegroup "$rgw_zonegroup" \
                --rgw-zone "$rgw_zone" \
                --master \
                --default ${endpointArg}
            else
              ${zoneModifyCmd}
            fi

            rgw_admin period update --rgw-realm "$rgw_realm" --commit >/dev/null 2>&1 || true

            ceph_cmd orch apply rgw \
              "$rgw_service" \
              --realm "$rgw_realm" \
              --zone "$rgw_zone" \
              --placement "$rgw_placement" \
              --port "$rgw_port" \
              ${sslPortArg}

            ceph_cmd orch start "rgw.$rgw_service" >/dev/null 2>&1 || true

            rgw_endpoint_ready=0
            if [ -n "$rgw_endpoint" ]; then
              for _ in $(seq 1 30); do
                if ceph_cmd_timeout 10 orch ps --service_name "rgw.$rgw_service" --format yaml 2>/dev/null \
                  | grep -q "status_desc: running"; then
                  rgw_endpoint_ready=1
                  break
                fi
                sleep 2
              done
              if [ "$rgw_endpoint_ready" -ne 1 ]; then
                echo "cephadm-rgw: rgw.$rgw_service is not running yet; bucket reconcile deferred" >&2
              fi
            fi

            ${userCommands}
            ${bucketCommands}
          '';
      };

      systemd.services.cephadm-mon-update = lib.mkIf cfg.monUpdate.enable {
        description = "Ceph monitor address update";
        after = [
          "network-online.target"
          "cephadm-runtime-daemons.service"
          "cephadm-cephadm-path.service"
          "cephadm-bootstrap.service"
        ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = cephadmPath;
        unitConfig.ConditionPathExists = "/etc/ceph/ceph.conf";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart =
            let
              targetAddr = if cfg.monUpdate.address != null then cfg.monUpdate.address else "";
              monName = if cfg.monUpdate.name != null then cfg.monUpdate.name else "";
              legacyAddr = if cfg.monUpdate.legacyAddress != null then cfg.monUpdate.legacyAddress else "";
              legacyPrefix = cfg.monUpdate.legacyPrefixLength;
              inherit (cfg.monUpdate) v2Port;
            in
            pkgs.writeShellScript "cephadm-mon-update" ''
              set -euo pipefail
              if [ -n "${legacyAddr}" ]; then
                ip addr add ${legacyAddr}/${toString legacyPrefix} dev lo 2>/dev/null || true
                trap 'ip addr del ${legacyAddr}/${toString legacyPrefix} dev lo 2>/dev/null || true' EXIT
              fi
              fsid=""
              if [ -f /etc/ceph/ceph.conf ]; then
                fsid="$(awk '/^[[:space:]]*fsid[[:space:]]*=/{print $3; exit}' /etc/ceph/ceph.conf || true)"
              fi

              keyring="/etc/ceph/ceph.client.admin.keyring"
              if [ ! -s "$keyring" ]; then
                echo "ceph mon update: missing admin keyring at $keyring" >&2
                exit 1
              fi
              ceph_bin="${cephPkg}/bin/ceph"
              format_addrs() {
                local host="$1"
                case "$host" in
                  (*[!0-9.:]*)
                    printf 'v2:%s:%s' "$host" "${toString v2Port}"
                    ;;
                  (*)
                    printf 'v2:%s:%s' "$host" "${toString v2Port}"
                    ;;
                esac
              }

              ceph_cmd() {
                "$ceph_bin" -m "$connect_addrs" -n client.admin -k "$keyring" "$@"
              }

              if [ -z "${targetAddr}" ]; then
                echo "ceph mon update: target address not set" >&2
                exit 0
              fi

              mon=""
              mon_unit=""
              if [ -n "${monName}" ]; then
                mon="${monName}"
                if [ -n "$fsid" ] && [ -f "/run/systemd/system/ceph-''${fsid}@.service" ]; then
                  mon_unit="ceph-''${fsid}@mon.''${mon}.service"
                  if ! systemctl is-active --quiet "$mon_unit"; then
                    systemctl start "$mon_unit" || true
                    for _ in $(seq 1 15); do
                      if systemctl is-active --quiet "$mon_unit"; then
                        break
                      fi
                      sleep 2
                    done
                  fi
                fi
              fi

              mon_dump=""
              connect_addrs=""
              for _ in $(seq 1 15); do
                for addr in ${legacyAddr} ${targetAddr}; do
                  if [ -z "$addr" ]; then
                    continue
                  fi
                  candidate_addrs="$(format_addrs "$addr")"
                  mon_dump="$(timeout 10 "$ceph_bin" -m "$candidate_addrs" -n client.admin -k "$keyring" mon dump -f json 2>/dev/null || true)"
                  if [ -n "$mon_dump" ]; then
                    connect_addrs="$candidate_addrs"
                    break 2
                  fi
                done
                sleep 2
              done

              if [ -z "$mon_dump" ]; then
                echo "ceph mon update: unable to read monmap; skipping" >&2
                exit 0
              fi

              if [ -z "$mon" ]; then
                mon_count="$(printf '%s' "$mon_dump" | ${pkgs.jq}/bin/jq '.mons | length')"
                if [ "$mon_count" -ne 1 ]; then
                  echo "ceph mon update: mon name required when more than one mon exists" >&2
                  exit 1
                fi
                mon="$(printf '%s' "$mon_dump" | ${pkgs.jq}/bin/jq -r '.mons[0].name')"
                if [ -n "$fsid" ] && [ -f "/run/systemd/system/ceph-''${fsid}@.service" ]; then
                  mon_unit="ceph-''${fsid}@mon.''${mon}.service"
                fi
              fi

              desired_addrs="$(format_addrs "${targetAddr}")"
              current_addrs="$(printf '%s' "$mon_dump" | ${pkgs.jq}/bin/jq -r --arg mon "$mon" '.mons[] | select(.name == $mon) | .public_addrs.addrvec | map(.addr) | join(",")')"
              if [ "$current_addrs" = "$desired_addrs" ]; then
                exit 0
              fi

              ceph_cmd mon set-addrs "$mon" "$desired_addrs"

              if [ -n "$fsid" ] && [ -n "$mon_unit" ]; then
                systemctl try-restart "$mon_unit" || true
              fi
            '';
        };
      };

      systemd.services.cephadm-runtime-daemons = lib.mkIf cfg.bootstrap.enable {
        description = "Install/start cephadm runtime daemon units";
        after = [
          "network-online.target"
          "cephadm-bootstrap.service"
        ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = cephadmPath;
        unitConfig.ConditionPathExists = "/etc/ceph/ceph.conf";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script =
          let
            monName = if cfg.monUpdate.name != null then cfg.monUpdate.name else hostName;
          in
          ''
            set -euo pipefail
            keyring="/etc/ceph/ceph.client.admin.keyring"
            if [ ! -s "$keyring" ]; then
              echo "cephadm-runtime-daemons: admin keyring missing; skipping" >&2
              exit 0
            fi

            fsid="$(awk '/^[[:space:]]*fsid[[:space:]]*=/{print $3; exit}' /etc/ceph/ceph.conf || true)"
            if [ -z "$fsid" ]; then
              echo "cephadm-runtime-daemons: fsid not found in ceph.conf; skipping" >&2
              exit 0
            fi

            shim_dir="/run/cephadm-systemctl-shim"
            install -d -m 0755 "$shim_dir"
            cat >"$shim_dir/systemctl" <<'SH'
            #!/usr/bin/env bash
            set -euo pipefail
            real="${pkgs.systemd}/bin/systemctl"
            cmd="${"1:-"}"
            case "$cmd" in
              enable|disable|preset|reenable|link)
                exec "$real" --runtime "$@"
                ;;
              *)
                exec "$real" "$@"
                ;;
            esac
            SH
            chmod 0755 "$shim_dir/systemctl"
            export PATH="$shim_dir:${cephadmBinPath}:$PATH"

            mon_name="${monName}"
            mgr_name="$(
              find "/var/lib/ceph/$fsid" -maxdepth 1 -type d -name "mgr.${hostName}.*" -printf '%f\n' \
                | sed -e 's/^mgr\.//' \
                | sort \
                | head -n1
            )"

            ${cephPkg}/bin/cephadm --unit-dir /run/systemd/system unit-install --fsid "$fsid" --name "mon.$mon_name" >/dev/null
            if [ -n "$mgr_name" ]; then
              ${cephPkg}/bin/cephadm --unit-dir /run/systemd/system unit-install --fsid "$fsid" --name "mgr.$mgr_name" >/dev/null
            else
              echo "cephadm-runtime-daemons: no mgr.<host> data directory found; mon only" >&2
            fi

            systemctl daemon-reload
            systemctl start "ceph-$fsid@mon.$mon_name.service" || true
            if [ -n "$mgr_name" ]; then
              systemctl start "ceph-$fsid@mgr.$mgr_name.service" || true
            fi
          '';
      };

      systemd.services.cephadm-cephadm-path = {
        description = "Cephadm path configuration";
        after = [
          "network-online.target"
          "cephadm-runtime-daemons.service"
          "cephadm-bootstrap.service"
        ];
        wants = [
          "network-online.target"
          "cephadm-runtime-daemons.service"
        ];
        wantedBy = [ "multi-user.target" ];
        path = cephadmPath;
        unitConfig.ConditionPathExists = "/etc/ceph/ceph.conf";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = 30;
          ExecStart =
            let
              monCandidates =
                let
                  rawCandidates = [
                    cfg.monUpdate.address
                    cfg.bootstrap.monIp
                  ]
                  ++ cfg.monHosts;
                in
                lib.concatStringsSep " " (lib.filter (host: host != null && host != "") rawCandidates);
              inherit (cfg.monUpdate) v2Port;
            in
            pkgs.writeShellScript "cephadm-cephadm-path" ''
              set -euo pipefail
              keyring="/etc/ceph/ceph.client.admin.keyring"
              ceph_bin="${cephPkg}/bin/ceph"
              connect_addrs=""
              format_addrs() {
                local host="$1"
                case "$host" in
                  (*[!0-9.:]*)
                    printf 'v2:%s:%s' "$host" "${toString v2Port}"
                    ;;
                  (*)
                    printf 'v2:%s:%s' "$host" "${toString v2Port}"
                    ;;
                esac
              }
              if [ -s "$keyring" ]; then
                for addr in ${monCandidates}; do
                  if [ -z "$addr" ]; then
                    continue
                  fi
                  candidate_addrs="$(format_addrs "$addr")"
                  if timeout 10 "$ceph_bin" -m "$candidate_addrs" -n client.admin -k "$keyring" status >/dev/null 2>&1; then
                    connect_addrs="$candidate_addrs"
                    break
                  fi
                done
              fi

              ceph_cmd() {
                if [ -n "$connect_addrs" ] && [ -s "$keyring" ]; then
                  "$ceph_bin" -m "$connect_addrs" -n client.admin -k "$keyring" "$@"
                else
                  ${cephadm} shell -- ceph "$@"
                fi
              }

              ceph_cmd_timeout() {
                local timeout_secs="$1"
                shift
                if [ -n "$connect_addrs" ] && [ -s "$keyring" ]; then
                  timeout "$timeout_secs" "$ceph_bin" -m "$connect_addrs" -n client.admin -k "$keyring" "$@"
                else
                  timeout "$timeout_secs" ${cephadm} shell -- ceph "$@"
                fi
              }

              fsid="$(ceph_cmd_timeout 10 fsid 2>/dev/null || true)"
              if [ -z "$fsid" ]; then
                echo "cephadm path: cluster not reachable; retrying" >&2
                exit 1
              fi

              cephadm_path="${if cfg.bootstrap.enable then cephadmMgrPathContainer else cephadmMgrPathHost}"
              if [ "${if cfg.bootstrap.enable then "1" else "0"}" = "1" ]; then
                host_cephadm_path="/var/run/ceph/$fsid/cephadm-orch"
                install -d -m 0755 -o ceph -g ceph "/var/run/ceph/$fsid"
                install -D -m 0755 -o ceph -g ceph ${cephadmMgrContainerWrapper} "$host_cephadm_path"
              else
                install -d -m 0755 -o ceph -g ceph /run/ceph
                install -D -m 0755 -o ceph -g ceph ${cephadmMgrWrapper} "$cephadm_path"
              fi

              current="$(
                ceph_cmd config get mgr cephadm_path 2>/dev/null || true
              )"
              path_changed=0
              if [ "$current" != "$cephadm_path" ]; then
                ceph_cmd config set mgr cephadm_path "$cephadm_path"
                path_changed=1
              fi
              ceph_cmd config set mgr mgr/cephadm/mode root >/dev/null 2>&1 || true

              ceph_cmd mgr module enable cephadm >/dev/null 2>&1 || true
              ceph_cmd config set mgr mgr/orchestrator/orchestrator cephadm >/dev/null 2>&1 || true
              orch_ready=0
              for _ in $(seq 1 6); do
                if ceph_cmd_timeout 10 orch status >/dev/null 2>&1; then
                  orch_ready=1
                  break
                fi
                sleep 2
              done
              if [ "$orch_ready" -ne 1 ] && [ "$path_changed" -eq 1 -o "${
                if cfg.bootstrap.enable then "1" else "0"
              }" = "1" ]; then
                active_mgr="$(
                  ceph_cmd mgr dump 2>/dev/null | sed -n 's/.*"active_name": "\([^"]*\)".*/\1/p' | head -n1
                )"
                if [ -n "$active_mgr" ]; then
                  ceph_cmd mgr fail "$active_mgr" >/dev/null 2>&1 || true
                  sleep 8
                  for _ in $(seq 1 8); do
                    if ceph_cmd_timeout 10 orch status >/dev/null 2>&1; then
                      orch_ready=1
                      break
                    fi
                    sleep 2
                  done
                fi
              fi
              if [ "$orch_ready" -ne 1 ]; then
                echo "cephadm path: ceph orch unavailable after updating cephadm_path; leaving path configured and continuing" >&2
                exit 0
              fi
              if [ "${if cfg.bootstrap.singleHostDefaults then "1" else "0"}" = "1" ]; then
                ceph_cmd orch apply mon --placement "count:1" >/dev/null 2>&1 || true
                ceph_cmd orch apply mgr --placement "count:1" >/dev/null 2>&1 || true
              fi
              if [ "${if cfg.osd.devices != [ ] then "1" else "0"}" = "1" ]; then
                ceph_cmd config set mgr mgr/cephadm/warn_on_stray_daemons false >/dev/null 2>&1 || true
              fi
            '';
        };
      };

      security.sudo.extraRules = lib.mkIf cfg.cephadm.useSudo [
        {
          users = [ "ceph" ];
          commands = [
            {
              command = "${cephadm}";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    })
    # Only create client ceph.conf when client is enabled AND bootstrap is NOT enabled
    # When bootstrap is enabled, cephadm manages /etc/ceph/ceph.conf
    (lib.mkIf (cfg.client.enable && !cfg.bootstrap.enable) (
      let
        confRel = lib.removePrefix "/etc/" cfg.client.confFile;
        monHosts = formatMonHosts cfg.client.monHosts cfg.client.monPort;
        confLines = lib.filter (line: line != "") [
          "[global]"
          (lib.optionalString (cfg.client.clusterName != "ceph") "cluster = ${cfg.client.clusterName}")
          (lib.optionalString (cfg.client.fsid != null) "fsid = ${cfg.client.fsid}")
          "mon_host = ${monHosts}"
          (lib.optionalString (
            cfg.client.publicNetwork != null
          ) "public_network = ${cfg.client.publicNetwork}")
          cfg.client.extraConfig
        ];
        confText = lib.concatStringsSep "\n" confLines + "\n";
      in
      {
        assertions = [
          {
            assertion = cfg.client.monHosts != [ ];
            message = "lukasf.ceph.client.monHosts must be set when enabling the Ceph client.";
          }
          {
            assertion = lib.hasPrefix "/etc/" cfg.client.confFile;
            message = "lukasf.ceph.client.confFile must live under /etc.";
          }
        ];

        environment.etc."${confRel}".text = confText;
      }
    ))
  ];
}
