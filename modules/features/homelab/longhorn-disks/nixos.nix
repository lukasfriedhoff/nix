{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.longhornDisks;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  hostName = config.networking.hostName;

  longhornDisks = lib.filterAttrs (_: disk: disk.host == hostName && disk.purpose == "longhorn") (
    import ../../../../resources/homelab/disks.nix
  );
  longhornDiskIds = builtins.attrNames longhornDisks;
  longhornDiskIndex = lib.listToAttrs (
    lib.imap0 (index: diskId: {
      name = diskId;
      value = index + 1;
    }) longhornDiskIds
  );

  serviceName = "${hostName}-longhorn-disks";
  keyPath = config.sops.secrets.${cfg.secretName}.path;
  orderBeforeK3s = cfg.orderBeforeK3s && config.services.k3s.enable;
in
{
  options.homelab.longhornDisks = {
    enable = mkEnableOption "LUKS unlock and mount of the host's Longhorn data disks";

    secretName = mkOption {
      type = types.str;
      default = "${hostName}-longhorn-luks-key";
      defaultText = lib.literalExpression ''"''${config.networking.hostName}-longhorn-luks-key"'';
      description = "Name of the sops secret holding the shared LUKS passphrase.";
    };

    sopsFile = mkOption {
      type = types.nullOr (types.either types.path types.str);
      default = null;
      description = ''
        Encrypted sops file for the LUKS passphrase. When set, the module
        declares sops.secrets.''${secretName}; when null the host is
        expected to declare the secret itself.
      '';
    };

    mountBase = mkOption {
      type = types.str;
      default = "/var/lib/longhorn-disk";
      description = "Mountpoint prefix; disk N is mounted at <mountBase>N.";
    };

    mode = mkOption {
      type = types.str;
      default = "0700";
      description = "Permissions applied to each mountpoint after mounting.";
    };

    orderBeforeK3s = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Order the unlock unit before k3s.service and make k3s require it,
        so kubelet never starts without its Longhorn disks. Only applies
        when k3s is enabled on the host.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = longhornDiskIds != [ ];
        message = "homelab.longhornDisks: no longhorn disks registered for ${hostName} in resources/homelab/disks.nix.";
      }
    ];

    sops.secrets = mkIf (cfg.sopsFile != null) {
      ${cfg.secretName} = {
        inherit (cfg) sopsFile;
        format = "binary";
        mode = "0400";
        owner = "root";
      };
    };

    systemd.services.${serviceName} = {
      description = "Unlock and mount ${hostName} Longhorn data disks";
      # sops-nix installs secrets from the setupSecrets activation script, not a
      # systemd unit, so there is no sops-install-secrets.service to order on.
      # Requiring a unit that does not exist makes switch-to-configuration abort.
      after = [ "systemd-udev-settle.service" ];
      before = lib.optionals orderBeforeK3s [ "k3s.service" ];
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
          # what left srv9 with k3s down and its Longhorn disks unmounted.
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
            test -r ${keyPath}
            # Strip CR/LF before feeding to cryptsetup so the on-disk passphrase
            # matches what deploy-from-iso.sh / new-host.sh wrote at install time
            # (both apply `tr -d '\r\n'` to the SOPS payload).
            ${pkgs.coreutils}/bin/tr -d '\r\n' \
              < ${keyPath} \
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
          chmod ${cfg.mode} "$mountpoint"
        }

        ${lib.concatStringsSep "\n" (
          map (diskId: ''
            unlockMount /dev/disk/by-id/${diskId}-part1 cryptlonghorn${
              toString longhornDiskIndex.${diskId}
            } ${cfg.mountBase}${toString longhornDiskIndex.${diskId}}
          '') longhornDiskIds
        )}
      '';
    };

    systemd.services.k3s = mkIf orderBeforeK3s {
      after = [ "${serviceName}.service" ];
      requires = [ "${serviceName}.service" ];
    };
  };
}
