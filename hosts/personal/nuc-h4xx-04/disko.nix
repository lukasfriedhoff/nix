{
  # Internal BIWIN NVMe only. The three USB disks this machine carried as
  # srv2 (Crucial BX500, SanDisk, Seagate 4TB) were Longhorn storage and are
  # physically removed - see resources/homelab/disks.nix history.
  #
  # As srv2 the root partition was a fixed 100G of a 512G device, leaving
  # ~350G unused because the bulk data lived on the USB disks. A workstation
  # has no reason for that, so root now takes the remainder of the disk.
  # Swap is sized above RAM (16G) so hibernate works.
  disko.devices.disk.main = {
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
        swap = {
          priority = 2;
          size = "20G";
          content = {
            type = "swap";
            discardPolicy = "both";
            resumeDevice = true;
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
}
