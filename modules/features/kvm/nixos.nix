{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.kvm;
in
{
  options.lukasf.kvm = {
    enable = lib.mkEnableOption "QEMU/KVM host";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.libvirt
      pkgs.qemu_kvm
      pkgs.virtiofsd
      pkgs.virt-top
    ];

    virtualisation.libvirtd.enable = true;
    virtualisation.libvirtd.nss.enableGuest = true;
    virtualisation.libvirtd.qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
    };
  };
}
