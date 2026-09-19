# The personal desktop as a Kubernetes-streamed container: the real Sway
# session with the full Home Manager profile and stylix theming (the "tux"
# desktop identity), running on the wlroots headless backend and captured
# by Selkies over Wayland. Built as an OCI image via the
# cloud-desktop-image package; container.nix carries the pod overrides.
{
  linuxUser,
  pkgs,
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
    # Without the Home Manager config Sway starts on the stock one, which
    # never reaches sway-session.target; wait for the dotfile instead of
    # racing it (linger-users is ordered after HM activation as well).
    unitConfig.ConditionPathExists = "%h/.config/sway/config";
    environment = {
      WLR_BACKENDS = "headless";
      WLR_LIBINPUT_NO_DEVICES = "1";
      WLR_HEADLESS_OUTPUTS = "1";
      # Without a usable render node wlroots refuses llvmpipe and exits;
      # a slow desktop beats a black one.
      WLR_RENDERER_ALLOW_SOFTWARE = "1";
    };
    serviceConfig = {
      ExecStart = "/etc/profiles/per-user/${linuxUser}/bin/sway";
      # Start the session target here rather than relying on the exec line
      # inside the Home Manager sway config: in a pod that line does not
      # reliably fire, and without it graphical-session.target — which
      # selkies is wantedBy — never activates. sway-session.target is a
      # regular unit that BindsTo graphical-session.target, so starting it
      # is both allowed and sufficient (graphical-session.target itself is
      # passive: starting it directly exits 4 and, from ExecStartPost, that
      # failure takes Sway down with it).
      ExecStartPost = pkgs.writeShellScript "sway-session-up" ''
        for _ in $(seq 1 50); do
          for s in wayland-1 wayland-0; do
            if [ -S "$XDG_RUNTIME_DIR/$s" ]; then
              systemctl --user set-environment WAYLAND_DISPLAY="$s"
              exec systemctl --user start sway-session.target
            fi
          done
          sleep 0.2
        done
        echo "no wayland socket appeared; not starting the session target" >&2
        exit 1
      '';
      Restart = "always";
      RestartSec = 5;
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
