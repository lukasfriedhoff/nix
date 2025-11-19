{ ... }:

{
  # Placeholder hardware configuration.
  # Replace with the output of `nixos-generate-config` on the ASUS VivoBook T3300.
  fileSystems."/" =
    { device = "/dev/disk/by-uuid/629cc750-4edd-454f-a5e5-73d6627a4880";
      fsType = "ext4";
    };

  boot.initrd.luks.devices."luks-1364ad7e-96d9-4508-942b-23ec3cdfca5d".device = "/dev/disk/by-uuid/1364ad7e-96d9-4508-942b-23ec3cdfca5d";

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/C2C5-757E";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  swapDevices =
    [ { device = "/dev/disk/by-uuid/e149f2f1-519d-410f-b21b-d6e750bf5803"; }
    ];

}
