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
  # Nested inside the selkies capture compositor, so selkies owns the
  # session lifecycle: it starts first (wantedBy default.target), Sway
  # attaches to its socket, and the session target follows Sway.
  systemd.user.services.selkies.wantedBy = [ "default.target" ];

  systemd.user.services.sway-headless = {
    description = "Sway session nested in the Selkies capture compositor";
    wantedBy = [ "default.target" ];
    after = [ "selkies.service" ];
    requires = [ "selkies.service" ];
    # Without the Home Manager config Sway starts on the stock one, which
    # never reaches sway-session.target; wait for the dotfile instead of
    # racing it (linger-users is ordered after HM activation as well).
    unitConfig.ConditionPathExists = "%h/.config/sway/config";
    environment = {
      # A client of selkies' compositor, not its own backend: this is what
      # avoids the dmabuf import failure of direct capture.
      WLR_BACKENDS = "wayland";
      WLR_RENDERER_ALLOW_SOFTWARE = "1";
    };
    serviceConfig = {
      # WAYLAND_DISPLAY must name selkies' compositor socket, which only
      # exists once selkies is up; probe rather than assume an index.
      ExecStart = pkgs.writeShellScript "sway-nested" ''
        for _ in $(seq 1 100); do
          for s in wayland-1 wayland-0; do
            if [ -S "$XDG_RUNTIME_DIR/$s" ]; then
              export WAYLAND_DISPLAY="$s"
              exec /etc/profiles/per-user/${linuxUser}/bin/sway
            fi
          done
          sleep 0.2
        done
        echo "selkies compositor socket never appeared" >&2
        exit 1
      '';
      # Start the session target once Sway's own socket exists: selkies
      # auto-detects it as the app compositor for input and clipboard.
      # (sway-session.target is a regular unit that BindsTo the passive
      # graphical-session.target; starting the latter directly exits 4 and
      # from ExecStartPost that failure would kill Sway.)
      ExecStartPost = pkgs.writeShellScript "sway-session-up" ''
        for _ in $(seq 1 50); do
          if [ -S "$XDG_RUNTIME_DIR/wayland-2" ]; then
            systemctl --user set-environment WAYLAND_DISPLAY=wayland-2
            exec systemctl --user start sway-session.target
          fi
          sleep 0.2
        done
        echo "sway socket never appeared; not starting the session target" >&2
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
    # Wayland, and selkies composites: it runs its own compositor (the
    # capture target) and Sway nests inside it as a client, with input and
    # clipboard auto-routed to Sway's own socket.
    #
    # Capturing Sway directly (wayland.hostDisplay) does NOT work here:
    # wlroots cannot import the dmabufs pixelflux allocates and logs
    # "eglCreateImageKHR ... EGL_BAD_MATCH / createImageFromDmaBufs failed"
    # at frame rate, so the browser sits on "Waiting for stream" forever.
    # Nested, both sides are smithay/wlroots talking their own buffers and
    # the error is gone.
    wayland.enable = true;
    wayland.nested = true;
    headless.enable = false;
  };
}
