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

      encrypted = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use dm-crypt for OSDs managed by cephadm.";
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
        ExecStart = "${cephadm} shell -- ceph config set mon public_network ${cfg.bootstrap.publicNetwork}";
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
            encryptedFlag = lib.optionalString cfg.osd.encrypted "--encrypted";
            deviceList = lib.concatStringsSep " " cfg.osd.devices;
          in
          pkgs.writeShellScript "cephadm-osd-provision" ''
                        set -euo pipefail
                        if [ -z "${deviceList}" ]; then
                          echo "No OSD devices configured, skipping." >&2
                          exit 0
                        fi

                        for _ in $(seq 1 30); do
                          if ${cephadm} shell -- ceph status >/dev/null 2>&1; then
                            break
                          fi
                          sleep 2
                        done

                        devices_json="$(${cephadm} shell -- ceph orch device ls --format json | sed -n '/^[[:space:]]*\\[/,$p')"
                        if [ -z "$devices_json" ]; then
                          echo "Device list unavailable, attempting direct OSD adds." >&2
                          for dev in ${deviceList}; do
                            ${cephadm} shell -- ceph orch daemon add osd "${osdHost}:$dev" ${encryptedFlag} || true
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
                            ${cephadm} shell -- ceph orch daemon add osd "${osdHost}:$dev" ${encryptedFlag} || true
                          else
                            echo "Skipping $dev (not available for OSD provisioning)" >&2
                          fi
                        done
          '';
      };
    };
  };
}
