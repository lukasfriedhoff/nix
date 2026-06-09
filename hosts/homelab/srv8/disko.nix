{ lib, ... }:

let
  hostName = "srv8";
  homelabDisks = import ../../../resources/homelab/disks.nix;
  longhornDiskEntries = lib.filterAttrs (
    _: v: v.host == hostName && v.purpose == "longhorn"
  ) homelabDisks;
  longhornDiskIds = builtins.attrNames longhornDiskEntries;
  longhornDiskIndex = lib.listToAttrs (
    lib.imap0 (idx: diskId: {
      name = diskId;
      value = idx + 1;
    }) longhornDiskIds
  );
  longhornLuksKeyFiles = lib.unique (
    map (diskId: longhornDiskEntries.${diskId}.luksKeyFile or null) longhornDiskIds
  );
  longhornPasswordFiles = lib.unique (
    map (diskId: longhornDiskEntries.${diskId}.luksPasswordFile or null) longhornDiskIds
  );
in
{
  assertions = [
    {
      assertion = lib.length longhornDiskIds >= 1;
      message = "srv8 disko: expected at least one longhorn disk in resources/homelab/disks.nix.";
    }
    {
      assertion = lib.length longhornLuksKeyFiles == 1 && lib.head longhornLuksKeyFiles != null;
      message = "srv8 disko: longhorn disks must define exactly one shared luksKeyFile in resources/homelab/disks.nix.";
    }
    {
      assertion = lib.length longhornPasswordFiles == 1 && lib.head longhornPasswordFiles != null;
      message = "srv8 disko: longhorn disks must define exactly one shared luksPasswordFile in resources/homelab/disks.nix.";
    }
  ];

  disko.devices.disk = {
    main = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-FORESEE_512GB_SSD_MCT5342001673";
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
              settings.allowDiscards = true;
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
  // lib.genAttrs longhornDiskIds (diskId: {
    type = "disk";
    device = "/dev/disk/by-id/${diskId}";
    content = {
      type = "gpt";
      partitions.data = {
        size = "100%";
        content = {
          type = "luks";
          name = "cryptlonghorn${toString longhornDiskIndex.${diskId}}";
          passwordFile = lib.head longhornPasswordFiles;
          settings.allowDiscards = true;
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/var/lib/longhorn-disk${toString longhornDiskIndex.${diskId}}";
            mountOptions = [
              "defaults"
              "nofail"
              "discard"
            ];
            extraArgs = [
              "-L"
              "longhorn-disk${toString longhornDiskIndex.${diskId}}"
            ];
          };
        };
      };
    };
  });
}
