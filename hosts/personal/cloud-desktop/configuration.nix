# The personal desktop as a Kubernetes-streamed container: full Home
# Manager profile and stylix theming (the "tux" desktop identity), an i3
# session rendered from the same tiling definition as Sway (Wayland cannot
# be captured on the Xorg-dummy path), and Selkies streaming it to the
# browser. Built as an OCI image via the cloud-desktop-image package.
{
  linuxUser,
  ...
}:

{
  imports = [
    ../../common/default.nix
  ];

  networking.hostName = "cloud-desktop";

  # Desktop hosts normally inherit this from the GNOME module.
  nixpkgs.config.allowUnfree = true;

  # Elsewhere the GNOME module owns the user; this host has no DE module.
  users.users.${linuxUser} = {
    isNormalUser = true;
    description = "Lukas Friedhoff";
    extraGroups = [ "wheel" ];
    # Boots the user manager (and with it the sway-headless session) at
    # system start — nobody logs in to a pod.
    linger = true;
  };

  # The real daily-driver session: Sway with the user's full HM config
  # (waybar, wofi, the shared tiling bindings), running on the wlroots
  # headless backend as a lingering user service — no seat, no DM.
  desktop.sway.enable = true;
  systemd.user.services.sway-headless = {
    description = "Headless Sway session for Selkies streaming";
    wantedBy = [ "default.target" ];
    environment = {
      WLR_BACKENDS = "headless";
      WLR_LIBINPUT_NO_DEVICES = "1";
    };
    serviceConfig = {
      ExecStart = "/etc/profiles/per-user/${linuxUser}/bin/sway";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  # App stack only: no wireguardAddress, so the workstation module wires no
  # VPN; container.nix trims the rest that cannot run in a pod.
  desktop.personalWorkstation.enable = true;

  lukasf.selkies = {
    enable = true;
    # Reached through the k8s Service; Authelia on the ingress is the login
    # and a NetworkPolicy restricts pod ingress to traefik.
    public = true;
    openFirewall = true;
    basicAuth.enable = false;
    # Capture the Sway session (screencopy + virtual input), no Xorg dummy.
    wayland.enable = true;
    headless.enable = false;
  };
}
