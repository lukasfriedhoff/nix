{
  config,
  pkgs,
  lib,
  ...
}:

let
  homeDir = config.home.homeDirectory;
  podmanBin = lib.getExe pkgs.podman;
  timeZone = config.time.timeZone or "UTC";
  jdownloaderImage = "lscr.io/linuxserver/jdownloader2:latest";
  jdownloaderConfigDir = "${homeDir}/.local/share/jdownloader";
  jdownloaderDownloadDir = "${homeDir}/Downloads/JDownloader";
  userUid = toString (config.home.uid or 1000);
  userGid = toString (config.home.gid or 100);
in
{
  home.packages = lib.mkAfter [
    pkgs.podman
    pkgs.btop
  ];

  home.activation.ensureJDownloaderDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${jdownloaderConfigDir}" "${jdownloaderDownloadDir}"
  '';

  systemd.user.services = {
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
          ''
            ${podmanBin} create \
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
