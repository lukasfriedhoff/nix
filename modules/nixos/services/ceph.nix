{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.ceph;
  systemctlShim = pkgs.writeShellScriptBin "systemctl" ''
    set -euo pipefail
    runtime=0
    for arg in "$@"; do
      if [ "$arg" = "enable" ] || [ "$arg" = "reenable" ]; then
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
    findutils
    gawk
    gptfdisk
    gnugrep
    gnused
    iproute2
    iputils
    jq
    lvm2
    podman
    util-linux
  ];
  pythonWithCephadmDeps = pkgs.python3.withPackages (ps: [
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
  ]);
  pythonSite = pkgs.python3.sitePackages;
  cephadm = pkgs.writeShellScript "cephadm-with-deps" ''
    export PYTHONPATH="${pythonWithCephadmDeps}/${pythonSite}:''${PYTHONPATH:-}"
    exec ${cfg.package}/bin/cephadm ${lib.escapeShellArgs cephadmArgs} "$@"
  '';
  python = "${pkgs.python3}/bin/python3";
  hostName = config.networking.hostName;
  osdHost = cfg.osd.host;
in
{
  options.lukasf.ceph = {
    enable = lib.mkEnableOption "Ceph (cephadm-managed)";

    package = lib.mkPackageOption pkgs "ceph" { };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the default Ceph ports in the firewall.";
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
    };

    pools = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule (
          { ... }:
          {
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
          }
        )
      );
      default = [ ];
      description = "Ceph pools to create and configure.";
    };

    osd = {
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
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (!cfg.bootstrap.enable) || (cfg.bootstrap.monIp != null && cfg.bootstrap.monIp != "");
        message = "lukasf.ceph.bootstrap.monIp must be set when bootstrap is enabled.";
      }
    ];

    environment.systemPackages = [
      cfg.package
      pkgs.python3
    ];

    virtualisation.podman.enable = true;

    systemd.tmpfiles.rules = [
      "d /bin 0755 root root -"
      "L+ /bin/bash - - - - ${pkgs.bashInteractive}/bin/bash"
      "L+ /bin/rm - - - - ${pkgs.coreutils}/bin/rm"
      "d /etc/ceph 0755 root root -"
      "d /etc/logrotate.d 0755 root root -"
      "d /var/lib/ceph 0755 root root -"
    ];

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [
        3300
        6789
      ];
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
      path = cephadmPath;
      unitConfig = {
        ConditionPathExists = "!/etc/ceph/ceph.conf";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        BindPaths = [ "/run/systemd/system:/etc/systemd/system" ];
        ExecStart = lib.concatStringsSep " " (
          [
            cephadm
            "bootstrap"
            "--mon-ip"
            cfg.bootstrap.monIp
            "--allow-fqdn-hostname"
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
      };
    };

    systemd.services.cephadm-public-network = lib.mkIf (cfg.bootstrap.publicNetwork != null) {
      description = "Cephadm public network configuration";
      after = [ "cephadm-bootstrap.service" ];
      wants = [ "cephadm-bootstrap.service" ];
      wantedBy = [ "multi-user.target" ];
      path = cephadmPath;
      unitConfig.ConditionPathExists = "/etc/ceph/ceph.conf";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart =
          let
            publicNetwork = cfg.bootstrap.publicNetwork;
          in
          pkgs.writeShellScript "cephadm-public-network" ''
            set -euo pipefail
            fsid=""
            if [ -f /etc/ceph/ceph.conf ]; then
              fsid="$(awk '/^fsid[[:space:]]*=/{print $3; exit}' /etc/ceph/ceph.conf || true)"
            fi

            if [ -n "$fsid" ]; then
              exec ${cephadm} shell --fsid "$fsid" -- ceph config set mon public_network ${publicNetwork}
            fi

            exec ${cephadm} shell -- ceph config set mon public_network ${publicNetwork}
          '';
      };
    };

    systemd.services.cephadm-osd = lib.mkIf cfg.osd.autoProvision {
      description = "Cephadm OSD provisioning";
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
        ExecStart =
          let
            methodFlag = cfg.osd.method;
            dmcryptFlag = lib.optionalString cfg.osd.encrypted "--dmcrypt";
            zapDevicesFlag = lib.boolToString cfg.osd.zapDevices;
            deviceList = lib.concatStringsSep " " cfg.osd.devices;
          in
          pkgs.writeShellScript "cephadm-osd-provision" ''
                        set -euo pipefail
                        if [ -z "${deviceList}" ]; then
                          echo "No OSD devices configured, skipping." >&2
                          exit 0
                        fi

                        fsid=""
                        if [ -f /etc/ceph/ceph.conf ]; then
                          fsid="$(awk '/^fsid[[:space:]]*=/{print $3; exit}' /etc/ceph/ceph.conf || true)"
                        fi

                        ceph_cmd() {
                          if [ -n "$fsid" ]; then
                            ${cephadm} shell --fsid "$fsid" -- ceph "$@"
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

                        if [ "${zapDevicesFlag}" = "true" ]; then
                          for dev in ${deviceList}; do
                            wipefs --all --force "$dev" || true
                            sgdisk --zap-all "$dev" || true
                            partprobe "$dev" || true
                            ceph_cmd orch device zap "${osdHost}" "$dev" --force || true
                          done
                        fi

                        devices_json="$(ceph_cmd orch device ls --format json | sed -n '/^[[:space:]]*\\[/,$p' || true)"
                        if [ -z "$devices_json" ]; then
                          echo "Device list unavailable, attempting direct OSD adds." >&2
                          for dev in ${deviceList}; do
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
                          for dev in ${deviceList}; do
                            add_osd "$dev"
                          done
                          exit 0
                        fi

                        for dev in ${deviceList}; do
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

    systemd.services.cephadm-pools = lib.mkIf (cfg.pools != [ ]) {
      description = "Ceph pool setup";
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
        ExecStart =
          let
            allowPoolSizeOne = lib.any (pool: pool.size == 1) cfg.pools;
          in
          pkgs.writeShellScript "cephadm-pools" ''
            set -euo pipefail
            fsid=""
            if [ -f /etc/ceph/ceph.conf ]; then
              fsid="$(awk '/^fsid[[:space:]]*=/{print $3; exit}' /etc/ceph/ceph.conf || true)"
            fi

            ceph_cmd() {
              if [ -n "$fsid" ]; then
                ${cephadm} shell --fsid "$fsid" -- ceph "$@"
              else
                ${cephadm} shell -- ceph "$@"
              fi
            }

            for _ in $(seq 1 30); do
              if ceph_cmd status >/dev/null 2>&1; then
                break
              fi
              sleep 2
            done

            ${lib.optionalString allowPoolSizeOne ''
              ceph_cmd config set mon mon_allow_pool_size_one true || true
              ceph_cmd config set global mon_allow_pool_size_one true || true
            ''}

            pools_json="$(ceph_cmd osd pool ls --format json | sed -n '/^[[:space:]]*\\[/,$p' || true)"
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
                              ceph_cmd osd pool set "${pool.name}" size ${toString pool.size}
                              ${lib.optionalString (pool.minSize != null) ''
                                ceph_cmd osd pool set "${pool.name}" min_size ${toString pool.minSize}
                              ''}
              '') cfg.pools
            )}
          '';
      };
    };
  };
}
