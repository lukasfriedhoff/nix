{ ... }:

{
  # Placeholder hardware configuration.
  # Replace with the output of `nixos-generate-config` on the ASUS VivoBook T3300.
  fileSystems."/" = {
    device = "/dev/disk/by-label/ROOT";
    fsType = "ext4";
  };

  swapDevices = [ ];
}
