{ ... }:

{
  imports = [
    ../../common/default.nix
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # LUKS (keep your UUID)
  boot.initrd.luks.devices."luks-84295891-6d10-4a08-a2fc-442738205455".device =
    "/dev/disk/by-uuid/84295891-6d10-4a08-a2fc-442738205455";

  networking.hostName = "nix-vm-01";

  desktop.wireguardHomelab = {
    enable = true;
    address = "10.1.90.4/24";
  };
}
