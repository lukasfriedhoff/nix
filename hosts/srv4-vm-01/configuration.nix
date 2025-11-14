{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # LUKS (keep your UUID)
  boot.initrd.luks.devices."luks-84295891-6d10-4a08-a2fc-442738205455".device =
    "/dev/disk/by-uuid/84295891-6d10-4a08-a2fc-442738205455";

  networking.hostName = "nix-vm-01";
}
