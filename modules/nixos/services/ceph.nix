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
  cephadmOrch = pkgs.writeShellScriptBin "cephadm-orch" ''
    export PYTHONPATH="${pythonWithCephadmDeps}/${pythonSite}:''${PYTHONPATH:-}"
    exec ${cfg.package}/bin/cephadm ${lib.escapeShellArgs cephadmArgs} "$@"
  '';
  cephadmOrchPath = "${cephadmOrch}/bin/cephadm-orch";
  cephadmMgrPath = "/var/log/ceph/cephadm-orch";
  cephadmMgrWrapper = pkgs.writeTextFile {
    name = "cephadm-orch-wrapper.py";
    executable = true;
    text = ''
      #!/usr/bin/env python3
      import os
      import sys

      args = sys.argv[1:]
      os.environ["PATH"] = "${systemctlShim}/bin:" + os.environ.get("PATH", "")
      if "--unit-dir" not in args:
          args = ["--unit-dir", "${cfg.cephadm.unitDir}"] + args
      os.execv("${cephadm}", ["${cephadm}"] + args)
    '';
  };
  python = "${pkgs.python3}/bin/python3";
  hostName = config.networking.hostName;
  osdHost = cfg.osd.host;
  isNumericHost = host: builtins.match "^[0-9.:]+$" host != null;
  formatMonHost =
    host: port:
    if isNumericHost host then "v2:${host}:${toString port}" else "${host}:${toString port}";
  formatMonHosts = hosts: port: lib.concatMapStringsSep "," (host: formatMonHost host port) hosts;
in
{
  options.lukasf.ceph = {
    enable = lib.mkEnableOption "Ceph (cephadm/ceph-volume)";

    package = lib.mkPackageOption pkgs "ceph" { };

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
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = (!cfg.bootstrap.enable) || (cfg.bootstrap.monIp != null && cfg.bootstrap.monIp != "");
          message = "lukasf.ceph.bootstrap.monIp must be set when bootstrap is enabled.";
        }
      ];

      environment.systemPackages = [
        cfg.package
        pkgs.python3
        pkgs.cryptsetup
        pkgs.lvm2
        cephadmOrch
      ];

      virtualisation.podman.enable = true;

      users.groups.ceph = { };
      users.users.ceph = {
        isSystemUser = true;
        group = "ceph";
        home = "/var/lib/ceph";
        shell = "${pkgs.shadow}/bin/nologin";
      };

      systemd.tmpfiles.rules = [
        "d /bin 0755 root root -"
        "L+ /bin/bash - - - - ${pkgs.bashInteractive}/bin/bash"
        "L+ /bin/rm - - - - ${pkgs.coreutils}/bin/rm"
        "d /etc/ceph 0755 root root -"
        "d /etc/logrotate.d 0755 root root -"
        "d /var/lib/ceph 0755 root root -"
        "d /var/log/ceph 0755 root root -"
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
              targetAddr = if cfg.monUpdate.address != null then cfg.monUpdate.address else cfg.bootstrap.monIp;
              legacyAddr = cfg.monUpdate.legacyAddress;
              v1Port = cfg.monUpdate.v1Port;
              v2Port = cfg.monUpdate.v2Port;
            in
            pkgs.writeShellScript "cephadm-public-network" ''
              set -euo pipefail
              fsid=""
              if [ -f /etc/ceph/ceph.conf ]; then
                fsid="$(awk '/^fsid[[:space:]]*=/{print $3; exit}' /etc/ceph/ceph.conf || true)"
              fi

              keyring="/etc/ceph/ceph.client.admin.keyring"
              if [ ! -s "$keyring" ]; then
                echo "ceph public network: missing admin keyring at $keyring" >&2
                exit 1
              fi
              ceph_bin="${cfg.package}/bin/ceph"
              format_addrs() {
                local host="$1"
                case "$host" in
                  (*[!0-9.:]*)
                    printf '%s:%s,%s:%s' "$host" "${toString v2Port}" "$host" "${toString v1Port}"
                    ;;
                  (*)
                    printf 'v2:%s:%s,v1:%s:%s' "$host" "${toString v2Port}" "$host" "${toString v1Port}"
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
                echo "ceph public network: unable to connect to mon for config update" >&2
                exit 1
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
                  v1Port = cfg.monUpdate.v1Port;
                  v2Port = cfg.monUpdate.v2Port;
                in
                pkgs.writeShellScript "cephadm-osd-provision" ''
                              set -euo pipefail
                              if [ -z "${deviceList}" ]; then
                                echo "No OSD devices configured, skipping." >&2
                                exit 0
                              fi

                              keyring="/etc/ceph/ceph.client.admin.keyring"
                              ceph_bin="${cfg.package}/bin/ceph"
                              connect_addrs=""
                              format_addrs() {
                                local host="$1"
                                case "$host" in
                                  (*[!0-9.:]*)
                                    printf '%s:%s,%s:%s' "$host" "${toString v2Port}" "$host" "${toString v1Port}"
                                    ;;
                                  (*)
                                    printf 'v2:%s:%s,v1:%s:%s' "$host" "${toString v2Port}" "$host" "${toString v1Port}"
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

                              ceph_cmd config set mgr cephadm_path "${cephadmMgrPath}" >/dev/null 2>&1 || true

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

                              if [ "${zapDevicesFlag}" = "true" ]; then
                                for dev in $deviceList; do
                                  wipefs --all --force "$dev" || true
                                  sgdisk --zap-all "$dev" || true
                                  partprobe "$dev" || true
                                  ceph_cmd orch device zap "${osdHost}" "$dev" --force || true
                                done
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
                  cephVolume = "${cfg.package}/bin/ceph-volume";
                  cephBin = "${cfg.package}/bin/ceph";
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

                  if [ "${zapDevicesFlag}" = "true" ] && [ -s "${adminKeyring}" ]; then
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
                    if [ "${zapDevicesFlag}" = "true" ]; then
                      ${cephVolume} lvm zap --destroy "$resolved" || true
                      ${cephVolume} raw zap --destroy "$resolved" || true
                      wipefs --all --force "$resolved" || true
                      sgdisk --zap-all "$resolved" || true
                      partprobe "$resolved" || true
                      blockdev --flushbufs "$resolved" || true
                      udevadm settle --timeout=10 || true
                    fi
                    ${cephVolume} lvm create --data "$resolved" --no-systemd ${dmcryptFlag}
                  done
                '';
            };
          };

      systemd.services.ceph-volume-osd-activate = lib.mkIf (cfg.osd.provisioner == "ceph-volume") {
        description = "Ceph OSD activation (ceph-volume)";
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
          KillMode = "none";
          TimeoutSec = 0;
          ExecStart = pkgs.writeShellScript "ceph-volume-osd-activate" ''
            set -euo pipefail
            admin_keyring="/etc/ceph/ceph.client.admin.keyring"
            ceph_bin="${cfg.package}/bin/ceph"
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
                    if ! timeout 5 "$ceph_bin" -n client.admin -k "$admin_keyring" \
                      auth get "client.osd-lockbox.$fsid" >/dev/null 2>&1; then
                      "$ceph_bin" -n client.admin -k "$admin_keyring" \
                        auth get-or-create "client.osd-lockbox.$fsid" \
                        mon 'allow profile osd-lockbox' \
                        -o "$lockbox_keyring"
                      chown ceph:ceph "$lockbox_keyring"
                      chmod 0600 "$lockbox_keyring"
                    fi
                    "$ceph_bin" -n client.admin -k "$admin_keyring" \
                      auth caps "client.osd-lockbox.$fsid" \
                      mon 'allow profile osd-lockbox, allow command config-key get' \
                      >/dev/null 2>&1 || true
              done
            fi
            ${cfg.package}/bin/ceph-volume lvm activate --all --no-systemd
          '';
        };
      };

      systemd.services.cephadm-pools = lib.mkIf (cfg.pools != [ ]) {
        description = "Ceph pool setup";
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
              allowPoolSizeOne = lib.any (pool: pool.size == 1) cfg.pools;
              monCandidates =
                let
                  rawCandidates = [
                    cfg.monUpdate.address
                    cfg.bootstrap.monIp
                  ]
                  ++ cfg.monHosts;
                in
                lib.concatStringsSep " " (lib.filter (host: host != null && host != "") rawCandidates);
              v1Port = cfg.monUpdate.v1Port;
              v2Port = cfg.monUpdate.v2Port;
            in
            pkgs.writeShellScript "cephadm-pools" ''
              set -euo pipefail
              keyring="/etc/ceph/ceph.client.admin.keyring"
              ceph_bin="${cfg.package}/bin/ceph"
              connect_addrs=""
              format_addrs() {
                local host="$1"
                case "$host" in
                  (*[!0-9.:]*)
                    printf '%s:%s,%s:%s' "$host" "${toString v2Port}" "$host" "${toString v1Port}"
                    ;;
                  (*)
                    printf 'v2:%s:%s,v1:%s:%s' "$host" "${toString v2Port}" "$host" "${toString v1Port}"
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
                '') cfg.pools
              )}
            '';
        };
      };

      systemd.services.cephadm-mon-update = lib.mkIf cfg.monUpdate.enable {
        description = "Ceph monitor address update";
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
              targetAddr = cfg.monUpdate.address;
              monName = cfg.monUpdate.name;
              legacyAddr = cfg.monUpdate.legacyAddress;
              legacyPrefix = cfg.monUpdate.legacyPrefixLength;
              v1Port = cfg.monUpdate.v1Port;
              v2Port = cfg.monUpdate.v2Port;
            in
            pkgs.writeShellScript "cephadm-mon-update" ''
              set -euo pipefail
              if [ -n "${legacyAddr}" ]; then
                ip addr add ${legacyAddr}/${toString legacyPrefix} dev lo 2>/dev/null || true
                trap 'ip addr del ${legacyAddr}/${toString legacyPrefix} dev lo 2>/dev/null || true' EXIT
              fi
              fsid=""
              if [ -f /etc/ceph/ceph.conf ]; then
                fsid="$(awk '/^fsid[[:space:]]*=/{print $3; exit}' /etc/ceph/ceph.conf || true)"
              fi

              keyring="/etc/ceph/ceph.client.admin.keyring"
              if [ ! -s "$keyring" ]; then
                echo "ceph mon update: missing admin keyring at $keyring" >&2
                exit 1
              fi
              ceph_bin="${cfg.package}/bin/ceph"
              format_addrs() {
                local host="$1"
                case "$host" in
                  (*[!0-9.:]*)
                    printf '%s:%s,%s:%s' "$host" "${toString v2Port}" "$host" "${toString v1Port}"
                    ;;
                  (*)
                    printf 'v2:%s:%s,v1:%s:%s' "$host" "${toString v2Port}" "$host" "${toString v1Port}"
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
                echo "ceph mon update: unable to read monmap" >&2
                exit 1
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

      systemd.services.cephadm-cephadm-path = {
        description = "Cephadm path configuration";
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
              monCandidates =
                let
                  rawCandidates = [
                    cfg.monUpdate.address
                    cfg.bootstrap.monIp
                  ]
                  ++ cfg.monHosts;
                in
                lib.concatStringsSep " " (lib.filter (host: host != null && host != "") rawCandidates);
              v1Port = cfg.monUpdate.v1Port;
              v2Port = cfg.monUpdate.v2Port;
            in
            pkgs.writeShellScript "cephadm-cephadm-path" ''
              set -euo pipefail
              keyring="/etc/ceph/ceph.client.admin.keyring"
              ceph_bin="${cfg.package}/bin/ceph"
              connect_addrs=""
              format_addrs() {
                local host="$1"
                case "$host" in
                  (*[!0-9.:]*)
                    printf '%s:%s,%s:%s' "$host" "${toString v2Port}" "$host" "${toString v1Port}"
                    ;;
                  (*)
                    printf 'v2:%s:%s,v1:%s:%s' "$host" "${toString v2Port}" "$host" "${toString v1Port}"
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

              fsid="$(ceph_cmd fsid 2>/dev/null || true)"
              if [ -z "$fsid" ]; then
                echo "Failed to determine Ceph FSID" >&2
                exit 1
              fi

              if [ -n "$fsid" ]; then
                cephadm_path="/var/log/ceph/$fsid/cephadm-orch"
                install -D -m 0755 ${cephadmMgrWrapper} "$cephadm_path"
                ln -sf "$cephadm_path" "${cephadmMgrPath}"
              fi

              current="$(
                ceph_cmd config get mgr cephadm_path 2>/dev/null || true
              )"
              if [ "$current" != "${cephadmMgrPath}" ]; then
                ceph_cmd config set mgr cephadm_path "${cephadmMgrPath}"
              fi
            '';
        };
      };
    })
    (lib.mkIf cfg.client.enable (
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
