# Overrides that turn the desktop config into something a pod can run.
# Same trick as virtual05ContainerModules, extended for k8s realities:
# no bootloader, no resolved conflict, and none of the units that need
# hardware, a VPN key, or the sops age key (absent in the cluster).
{ lib, ... }:
{
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  networking.useHostResolvConf = lib.mkForce false;
  services.resolved.enable = lib.mkForce false;
  documentation.doc.enable = lib.mkForce false;

  # personalWorkstation turns gaming on; multi-GB of closure (and srv1's
  # unbuildable-FOD lesson) with nothing to render it in a pod.
  desktop.gaming.enable = lib.mkForce false;
  virtualisation.podman.enable = lib.mkForce false;
  # Wants NetworkManager, which the container profile strips.
  lukasf.protonvpn.enable = lib.mkForce false;
}
