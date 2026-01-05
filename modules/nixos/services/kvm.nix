{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.kvm;
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
      pkgs.libvirt
      pkgs.qemu_kvm
      pkgs.virtiofsd
      pkgs.virt-top
    ];

    virtualisation.libvirtd.enable = true;
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
        pkgs.libvirt
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
                            virsh secret-set-value --secret "${pool.secretUuid}" --base64 "$key"

                            if ! virsh pool-info "${pool.name}" >/dev/null 2>&1; then
                              cat >"/run/libvirt-ceph-pool-${pool.name}.xml" <<'XML'
              <pool type='rbd'>
                <name>${pool.name}</name>
                <source>
                  <name>${pool.pool}</name>
                  <auth type='ceph' username='client.${pool.user}'>
                    <secret uuid='${pool.secretUuid}'/>
                  </auth>
                </source>
              </pool>
              XML
                              virsh pool-define --file "/run/libvirt-ceph-pool-${pool.name}.xml"
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
