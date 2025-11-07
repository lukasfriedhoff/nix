{ ... }:

{
  # Placeholder hardware configuration. Replace with the output of
  # `nixos-generate-config --show-hardware-config` on the Supermicro host.
  fileSystems."/" = {
    device = "/dev/disk/by-label/ROOT";
    fsType = "ext4";
  };

  swapDevices = [ ];
}
