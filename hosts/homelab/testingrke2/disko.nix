{
  rootSerial,
  longhornSerial,
}:

{
  disko.devices.disk = {
    main = {
      type = "disk";
      device = "/dev/disk/by-id/virtio-${rootSerial}";
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

    longhorn = {
      type = "disk";
      device = "/dev/disk/by-id/virtio-${longhornSerial}";
      content = {
        type = "gpt";
        partitions.longhorn = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/var/lib/longhorn-disk1";
            mountOptions = [
              "defaults"
              "discard"
              "nofail"
            ];
          };
        };
      };
    };
  };
}
