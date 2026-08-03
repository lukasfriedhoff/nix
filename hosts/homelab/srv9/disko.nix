{ lib, ... }:

let
  hostName = "srv9";
  systemDiskId = "scsi-35002538b11337b60";
  homelabDisks = import ../../../resources/homelab/disks.nix;
  longhornDiskEntries = lib.filterAttrs (
    _: disk: disk.host == hostName && disk.purpose == "longhorn"
  ) homelabDisks;
  longhornDiskIds = builtins.attrNames longhornDiskEntries;
  longhornDiskIndex = lib.listToAttrs (
    lib.imap0 (index: diskId: {
      name = diskId;
      value = index + 1;
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
      assertion = lib.length longhornDiskIds == 7;
      message = "srv9 disko: expected seven Longhorn disks in resources/homelab/disks.nix.";
    }
    {
      assertion = lib.length longhornLuksKeyFiles == 1 && lib.head longhornLuksKeyFiles != null;
      message = "srv9 disko: Longhorn disks must define exactly one shared luksKeyFile.";
    }
    {
      assertion = lib.length longhornPasswordFiles == 1 && lib.head longhornPasswordFiles != null;
      message = "srv9 disko: Longhorn disks must define exactly one shared luksPasswordFile.";
    }
  ];

  disko.devices.disk = {
    system = {
      type = "disk";
      device = "/dev/disk/by-id/${systemDiskId}";
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
              mountOptions = [ "umask=0077" ];
              extraArgs = [
                "-n"
                "EFI"
              ];
            };
          };
          root = {
            size = "100%";
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
              "noauto"
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
