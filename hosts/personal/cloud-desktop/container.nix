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

  # kubelet bind-mounts /etc/resolv.conf with the cluster DNS; resolvconf
  # wrote through that bind mount and left the pod with an options-only
  # file and no nameserver at all.
  networking.resolvconf.enable = lib.mkForce false;

  # There is no DHCP in a pod — the address comes from CNI.
  networking.useDHCP = lib.mkForce false;

  # Home Manager activation picks $XDG_STATE_HOME/nix/profiles when it
  # exists, which keeps generations on the home PVC instead of the
  # ephemeral container layer.
  systemd.tmpfiles.rules = [
    "d /home/lukasf/.local 0755 lukasf users -"
    "d /home/lukasf/.local/state 0755 lukasf users -"
    "d /home/lukasf/.local/state/nix 0755 lukasf users -"
    "d /home/lukasf/.local/state/nix/profiles 0755 lukasf users -"
  ];

  # personalWorkstation turns gaming on; multi-GB of closure (and srv1's
  # unbuildable-FOD lesson) with nothing to render it in a pod.
  desktop.gaming.enable = lib.mkForce false;
  virtualisation.podman.enable = lib.mkForce false;
  # Wants NetworkManager, which the container profile strips.
  lukasf.protonvpn.enable = lib.mkForce false;
}
