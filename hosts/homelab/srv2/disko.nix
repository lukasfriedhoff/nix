{ lib, ... }:

let
  hostName = "srv2";
  # Keep data partitions equal-sized across mixed 1TB SSD models to avoid
  # mdadm interactive size confirmation (which aborts unattended installs).
  mdadmPartitionSize = "930G";
  homelabDisks = import ../../../resources/homelab/disks.nix;
  mdadmDiskEntries = lib.filterAttrs (_: v: v.host == hostName && v.purpose == "mdadm") homelabDisks;
  mdadmDiskIds = builtins.attrNames mdadmDiskEntries;
  mdadmLuksKeyFiles = lib.unique (
    map (diskId: mdadmDiskEntries.${diskId}.luksKeyFile or null) mdadmDiskIds
  );
  mdadmPasswordFiles = lib.unique (
    map (diskId: mdadmDiskEntries.${diskId}.luksPasswordFile or null) mdadmDiskIds
  );
in
{
  assertions = [
    {
      assertion = lib.length mdadmDiskIds >= 2;
      message = "srv2 disko: expected at least two mdadm disks in resources/homelab/disks.nix.";
    }
    {
      assertion = lib.length mdadmLuksKeyFiles == 1 && lib.head mdadmLuksKeyFiles != null;
      message = "srv2 disko: mdadm disks must define exactly one shared luksKeyFile in resources/homelab/disks.nix.";
    }
    {
      assertion = lib.length mdadmPasswordFiles == 1 && lib.head mdadmPasswordFiles != null;
      message = "srv2 disko: mdadm disks must define exactly one shared luksPasswordFile in resources/homelab/disks.nix.";
    }
  ];

  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-BIWIN_CE480V6D100-512G_2339093303875";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              priority = 1;
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                extraArgs = [
                  "-n"
                  "EFI"
                ];
              };
            };
            root = {
              size = "100G";
              content = {
                type = "luks";
                name = "cryptroot";
                passwordFile = "/tmp/luks.key";
                settings = {
                  allowDiscards = true;
                };
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
            swap = {
              size = "24G";
              content = {
                type = "swap";
                discardPolicy = "both";
              };
            };
          };
        };
      };
    }
    // lib.genAttrs mdadmDiskIds (diskId: {
      type = "disk";
      device = "/dev/disk/by-id/${diskId}";
      content = {
        type = "gpt";
        partitions = {
          mdadm = {
            size = mdadmPartitionSize;
            content = {
              type = "mdraid";
              name = "data";
            };
          };
        };
      };
    });

    mdadm.data = {
      type = "mdadm";
      level = 1;
      metadata = "1.2";
      content = {
        type = "luks";
        name = "cryptdata";
        initrdUnlock = false;
        # The plaintext for this key is decrypted at deploy-time from:
        #   secrets/profiles/personal/shared/${lib.head mdadmLuksKeyFiles}
        passwordFile = lib.head mdadmPasswordFiles;
        settings = {
          allowDiscards = true;
        };
        content = {
          type = "filesystem";
          format = "ext4";
          extraArgs = [
            "-L"
            "srv2-data"
          ];
        };
      };
    };
  };
}
