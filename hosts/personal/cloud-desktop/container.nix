# Overrides that turn the desktop config into something a pod can run.
#
# Two classes of override live here. The first is the usual container
# trimming: no bootloader, no DHCP, none of the units that want hardware,
# a VPN key or the sops age key (absent in the cluster).
#
# The second matters more: this pod is PRIVILEGED, so several NixOS units
# that look host-local actually reach srv8 itself — /proc/sys is shared
# and not namespaced, /nix/store is an overlayfs lower layer on the node's
# disk, and logind's suspend goes to the node's /sys/power/state. Anything
# in that class is force-disabled below with the reason attached.
{
  lib,
  pkgs,
  linuxUser,
  ...
}:
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

  # containerd bind-mounts both; setup-etc cannot rename over a bind mount
  # and the k8s versions (pod IP, pod name) are the ones we want.
  environment.etc.hosts.enable = false;
  environment.etc.hostname.enable = false;

  # --- Units that would reach out of the pod and act on srv8 ---------------

  # /proc/sys is rw and shared with the node: applying these would set the
  # node's kernel.core_pattern and kernel.poweroff_cmd to store paths that
  # exist only inside this image.
  systemd.suppressedSystemUnits = [ "systemd-sysctl.service" ];
  boot.kernel.sysctl = lib.mkForce { };

  # The store is the image. Optimising hardlink-dedupes an overlayfs lower
  # layer, which copies the whole closure up into the node's containerd
  # snapshot; GC would collect paths whose gcroots live on the ephemeral
  # layer, including the ones the persisted HM generations point at.
  nix.optimise.automatic = lib.mkForce false;
  nix.gc.automatic = lib.mkForce false;
  nix.gcRootsCleaner.enable = lib.mkForce false;

  # fstrim --listed-in /proc/self/mountinfo resolves to srv8's cryptroot
  # and to the Longhorn volume from in here. Trimming is their job.
  services.fstrim.enable = lib.mkForce false;

  # From the docker-container profile: there is no channel workflow in a
  # pod, the marker it checks is ephemeral so it re-runs every start, and
  # Before=sysinit.target makes its failure block the whole boot.
  systemd.services.nix-channel-init.enable = lib.mkForce false;

  # kubelet owns this pod's OOM policy.
  systemd.oomd.enable = lib.mkForce false;

  # --- Making the session actually start ----------------------------------

  # loginctl enable-linger starts user@1000 (and with it Sway) as soon as
  # multi-user is up, which beat Home Manager activation: Sway then came up
  # on the stock package config, never started sway-session.target, and
  # selkies — wantedBy=graphical-session.target — stayed dead.
  systemd.services.linger-users = {
    after = [ "home-manager-${linuxUser}.service" ];
    wants = [ "home-manager-${linuxUser}.service" ];
  };

  # The minimal profile (via docker-image.nix) switches these off, but a
  # desktop needs them for xdg-open and icon lookups.
  xdg.mime.enable = lib.mkForce true;
  xdg.icons.enable = lib.mkForce true;

  # /var/log is the container's ephemeral layer, and the repo's journald
  # caps are gated on networkmanager.enable (false here). Audit=no because
  # a privileged pod has CAP_AUDIT_READ and would ingest the NODE's audit
  # stream.
  services.journald.storage = "volatile";
  services.journald.extraConfig = ''
    RuntimeMaxUse=64M
    RuntimeKeepFree=64M
    Audit=no
  '';

  systemd.tmpfiles.rules = [
    # Home Manager picks $XDG_STATE_HOME/nix/profiles when it exists, which
    # keeps generations on the home PVC rather than the ephemeral layer.
    "d /home/${linuxUser}/.local 0755 ${linuxUser} users -"
    "d /home/${linuxUser}/.local/state 0755 ${linuxUser} users -"
    "d /home/${linuxUser}/.local/state/nix 0755 ${linuxUser} users -"
    "d /home/${linuxUser}/.local/state/nix/profiles 0755 ${linuxUser} users -"
    # fixSshPerms chmods this unconditionally and a fresh PVC has no ~/.ssh,
    # which aborts HM activation under set -e.
    "d /home/${linuxUser}/.ssh 0700 ${linuxUser} users -"
    "d /home/${linuxUser}/.ssh/config.d 0700 ${linuxUser} users -"
  ];

  # /var/lib/nixos/uid-map is on the ephemeral layer, so the UID is
  # reallocated every start; pin it or the PVC's files stop matching.
  users.users.${linuxUser}.uid = 1000;

  # --- Weight and dead ends ------------------------------------------------

  # personalWorkstation turns gaming on; multi-GB of closure (and srv1's
  # unbuildable-FOD lesson) with nothing to render it in a pod.
  desktop.gaming.enable = lib.mkForce false;
  virtualisation.podman.enable = lib.mkForce false;
  # Wants NetworkManager, which the container profile strips.
  lukasf.protonvpn.enable = lib.mkForce false;
  # No LLM backend in a streamed desktop; pure image weight.
  lukasf.llamaCpp.enable = lib.mkForce false;
  # No generation history in a pod, so the diff only ever fails activation.
  lukasf.nixosUpgradeDiff.enable = lib.mkForce false;

  home-manager.users.${linuxUser} = {
    # swayidle's AC probe finds no /sys/class/power_supply entry, takes the
    # battery branch, and would swaylock an account with no password after
    # 5 minutes — then ask logind to suspend srv8 after 10.
    services.swayidle.enable = lib.mkForce false;
    programs.swaylock.enable = lib.mkForce false;
    # Output hotplug and gamma control do not exist on a headless output;
    # both restart-loop into failed units.
    services.kanshi.enable = lib.mkForce false;
    services.gammastep.enable = lib.mkForce false;
    # Harvesting cluster-admin kubeconfigs over SSH from a browser-reachable
    # pod is not a thing we want; kubectl itself stays.
    programs.kubeconfig.refreshOnActivation = lib.mkForce false;
    # Wine plus two GitHub FODs, for a game that cannot run here.
    programs.icarusModManager.enable = lib.mkForce false;
    # Pin the headless output: wlroots' headless backend defaults to a
    # hardcoded 1280x720 with no mode set anywhere.
    wayland.windowManager.sway.config.output."HEADLESS-1".resolution = "1920x1080";
  };

  # mesa ships radeonsi_drv_video for srv8's Renoir; add the Intel stack so
  # the same image also hardware-encodes when scheduled on srv2.
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    libva-vdpau-driver
  ];
}
