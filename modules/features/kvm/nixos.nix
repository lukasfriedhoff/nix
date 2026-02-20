{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.kvm;
  libvirtPkg =
    if cfg.storage.backend == "ceph" then
      pkgs.libvirt.override { enableCeph = true; }
    else
      pkgs.libvirt;
  cephPools =
    if cfg.storage.ceph.pools != [ ] then
      cfg.storage.ceph.pools
    else
      [
        {
          name = cfg.storage.ceph.poolName;
          pool = cfg.storage.ceph.pool;
          user = cfg.storage.ceph.user;
          secretUuid = cfg.storage.ceph.secretUuid;
          keyringFile = cfg.storage.ceph.keyringFile;
          confFile = cfg.storage.ceph.confFile;
          monHost = cfg.storage.ceph.monHost;
          monPort = cfg.storage.ceph.monPort;
        }
      ];
in
{
  options.lukasf.kvm = {
    enable = lib.mkEnableOption "QEMU/KVM host";

    storage = {
      backend = lib.mkOption {
        type = lib.types.enum [
          "none"
          "ceph"
        ];
        default = "none";
        description = "Storage backend for libvirt (\"none\" means manual setup).";
      };

      ceph = {
        pools = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule (
              { ... }:
              {
                options = {
                  name = lib.mkOption {
                    type = lib.types.str;
                    description = "Libvirt storage pool name.";
                  };

                  pool = lib.mkOption {
                    type = lib.types.str;
                    description = "Ceph pool name.";
                  };

                  user = lib.mkOption {
                    type = lib.types.str;
                    description = "Ceph client user for libvirt (without the client. prefix).";
                  };

                  secretUuid = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    description = "Libvirt secret UUID to store the Ceph key.";
                  };

                  keyringFile = lib.mkOption {
                    type = lib.types.str;
                    description = "Path to the Ceph keyring for the libvirt client.";
                  };

                  confFile = lib.mkOption {
                    type = lib.types.str;
                    description = "Path to ceph.conf for libvirt RBD access.";
                  };

                  monHost = lib.mkOption {
                    type = lib.types.nullOr lib.types.str;
                    default = null;
                    description = "Ceph monitor hostname or IP for the RBD pool.";
                  };

                  monPort = lib.mkOption {
                    type = lib.types.int;
                    default = 3300;
                    description = "Ceph monitor port for the RBD pool (v2 default is 3300).";
                  };
                };
              }
            )
          );
          default = [ ];
          description = "Ceph-backed libvirt storage pools.";
        };

        poolName = lib.mkOption {
          type = lib.types.str;
          default = "ceph";
          description = "Libvirt storage pool name.";
        };

        pool = lib.mkOption {
          type = lib.types.str;
          default = "rbd";
          description = "Ceph pool name.";
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "libvirt";
          description = "Ceph client user for libvirt (without the client. prefix).";
        };

        secretUuid = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Libvirt secret UUID to store the Ceph key.";
        };

        keyringFile = lib.mkOption {
          type = lib.types.str;
          default = "/etc/ceph/ceph.client.libvirt.keyring";
          description = "Path to the Ceph keyring for the libvirt client.";
        };

        confFile = lib.mkOption {
          type = lib.types.str;
          default = "/etc/ceph/ceph.conf";
          description = "Path to ceph.conf for libvirt RBD access.";
        };

        monHost = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Ceph monitor hostname or IP for the single-pool setup.";
        };

        monPort = lib.mkOption {
          type = lib.types.int;
          default = 3300;
          description = "Ceph monitor port for the single-pool setup (v2 default is 3300).";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.storage.backend != "ceph" || lib.all (pool: pool.secretUuid != null) cephPools;
        message = "Each Ceph pool must define a secretUuid when using the Ceph backend.";
      }
    ];

    environment.systemPackages = [
      libvirtPkg
      pkgs.qemu_kvm
      pkgs.virtiofsd
      pkgs.virt-top
    ];

    virtualisation.libvirtd.enable = true;
    virtualisation.libvirtd.package = libvirtPkg;
    virtualisation.libvirtd.qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
    };

    systemd.services.libvirt-ceph-storage = lib.mkIf (cfg.storage.backend == "ceph") {
      description = "Libvirt Ceph storage pool setup";
      after = [
        "libvirtd.service"
        "network-online.target"
      ];
      wants = [
        "libvirtd.service"
        "network-online.target"
      ];
      wantedBy = [ "multi-user.target" ];
      path = [
        libvirtPkg
        pkgs.coreutils
        pkgs.gawk
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "libvirt-ceph-storage" ''
          set -euo pipefail
          ${lib.concatStringsSep "\n" (
            map (pool: ''
                            export CEPH_CONF="${pool.confFile}"
                            if [ ! -r "${pool.keyringFile}" ]; then
                              echo "Missing Ceph keyring: ${pool.keyringFile}" >&2
                              exit 1
                            fi

                            key="$(awk -F ' = ' '/key[[:space:]]*=/{print $2; exit}' "${pool.keyringFile}")"
                            if [ -z "$key" ]; then
                              echo "Failed to read key from ${pool.keyringFile}" >&2
                              exit 1
                            fi

                            if ! virsh secret-lookup-by-uuid "${pool.secretUuid}" >/dev/null 2>&1; then
                              cat >"/run/libvirt-ceph-secret-${pool.name}.xml" <<'XML'
              <secret ephemeral='no' private='yes'>
                <uuid>${pool.secretUuid}</uuid>
                <usage type='ceph'>
                  <name>client.${pool.user} secret</name>
                </usage>
              </secret>
              XML
                              virsh secret-define --file "/run/libvirt-ceph-secret-${pool.name}.xml"
                            fi
                            # Ceph keyring stores base64; libvirt wants raw bytes.
                            virsh secret-set-value --secret "${pool.secretUuid}" --base64 "$key"

                            mon_host="${toString pool.monHost}"
                            mon_port="${toString pool.monPort}"
                            host_xml=""
                            if [ -n "$mon_host" ] && [ "$mon_host" != "null" ]; then
                              host_xml="<host name='${pool.monHost}' port='${toString pool.monPort}'/>"
                            fi

                                          pool_xml="/run/libvirt-ceph-pool-${pool.name}.xml"
                                          printf '%s\n' \
                                            "<pool type='rbd'>" \
                                            "  <name>${pool.name}</name>" \
                                            "  <source>" \
                                            "    <name>${pool.pool}</name>" \
                                            > "$pool_xml"
                                          if [ -n "$host_xml" ]; then
                                            printf '    %s\n' "$host_xml" >> "$pool_xml"
                                          fi
                                          printf '%s\n' \
                                            "    <auth type='ceph' username='${pool.user}'>" \
                                            "      <secret uuid='${pool.secretUuid}'/>" \
                                            "    </auth>" \
                                            "  </source>" \
                                            "</pool>" \
                                            >> "$pool_xml"

                                          if virsh pool-info "${pool.name}" >/dev/null 2>&1; then
                                            current_sum="$(virsh pool-dumpxml "${pool.name}" | sha256sum | awk '{print $1}')"
                                            desired_sum="$(sha256sum "$pool_xml" | awk '{print $1}')"
                                            if [ "$current_sum" != "$desired_sum" ]; then
                                              virsh pool-destroy "${pool.name}" || true
                                              virsh pool-undefine "${pool.name}" || true
                                              virsh pool-define --file "$pool_xml"
                                            fi
                                          else
                                            virsh pool-define --file "$pool_xml"
                                          fi
                            virsh pool-autostart "${pool.name}"
                            virsh pool-start "${pool.name}" || true
            '') cephPools
          )}
        '';
      };
    };
  };
}
