_: {
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/ata-SanDisk_Ultra_II_960GB_162417421944";
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
            size = "100%";
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
        };
      };
    };
  };
}
