{ config, pkgs, lib, ... }:

let
  homeDir = config.home.homeDirectory;
  idleDimmer = pkgs.writeShellApplication {
    name = "gnome-idle-dimmer";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.upower
      pkgs.glib
    ];
    text = ''
      set -euo pipefail

      display_device="$(${pkgs.upower}/bin/upower -e | grep -m1 'DisplayDevice' || true)"
      if [ -z "$display_device" ]; then
        echo "gnome-idle-dimmer: could not find UPower DisplayDevice" >&2
        exit 1
      fi

      apply_timeout() {
        target="$1"
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.session idle-delay "$target"
      }

      last_state="__unset"
      while true; do
        state="$(${pkgs.upower}/bin/upower -i "$display_device" | ${pkgs.gawk}/bin/awk -F':' '/state/ {gsub(/ /, \"\", $2); print $2; exit}')"
        if [ -z "$state" ]; then
          sleep 30
          continue
        fi

        if [ "$state" != "$last_state" ]; then
          if [ "$state" = "discharging" ]; then
            apply_timeout 120
          else
            apply_timeout 300
          fi
          last_state="$state"
        fi

        sleep 30
      done
    '';
  };
  podmanBin = lib.getExe pkgs.podman;
  timeZone = config.time.timeZone or "UTC";
  jdownloaderImage = "lscr.io/linuxserver/jdownloader2:latest";
  jdownloaderConfigDir = "${homeDir}/.local/share/jdownloader";
  jdownloaderDownloadDir = "${homeDir}/Downloads/JDownloader";
  userUid = toString (config.home.uid or 1000);
  userGid = toString (config.home.gid or 100);
in
{
  home.packages = lib.mkAfter [ pkgs.podman pkgs.btop ];

  home.activation.ensureJDownloaderDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${jdownloaderConfigDir}" "${jdownloaderDownloadDir}"
  '';

  systemd.user.services = {
    "gnome-idle-dimmer" = {
      Unit = {
        Description = "Adjust GNOME idle dim timeout based on power source";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${idleDimmer}/bin/gnome-idle-dimmer";
        Restart = "on-failure";
        RestartSec = 5;
        Environment = [ "DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus" ];
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };

    "podman-jdownloader" = {
      Unit = {
        Description = "JDownloader 2 (Podman container)";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        ExecStartPre = [
          "${podmanBin} pull ${jdownloaderImage}"
          "${podmanBin} rm --ignore jdownloader"
          ''${podmanBin} create \
            --name jdownloader \
            --userns=keep-id \
            --volume ${jdownloaderConfigDir}:/config:rw \
            --volume ${jdownloaderDownloadDir}:/output:rw \
            --publish 127.0.0.1:5800:5800 \
            --publish 127.0.0.1:5900:5900 \
            --env PUID=${userUid} \
            --env PGID=${userGid} \
            --env TZ=${timeZone} \
            --label io.containers.autoupdate=registry \
            ${jdownloaderImage}''
        ];
        ExecStart = "${podmanBin} start --attach jdownloader";
        ExecStop = "${podmanBin} stop --ignore --time 10 jdownloader";
        ExecStopPost = "${podmanBin} rm --ignore jdownloader";
        Restart = "always";
        RestartSec = 15;
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
