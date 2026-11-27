{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.androidDeviceHost;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    optionalAttrs
    types
    ;
  adb = lib.getExe' cfg.package "adb";
in
{
  options.homelab.androidDeviceHost = {
    enable = mkEnableOption "hosting a USB-attached Android device for in-cluster automation and streaming";

    package = mkPackageOption pkgs "android-tools" { };

    group = mkOption {
      type = types.str;
      default = "adb";
      description = ''
        Group that owns the phone's USB device node and the adb server
        socket. Pods reach the socket by matching this group's gid.
      '';
    };

    socketPath = mkOption {
      type = types.str;
      default = "/run/adb/adb.sock";
      description = ''
        Unix socket the adb server listens on. adb has no client
        authentication at all, so the server never listens on TCP: the
        socket's filesystem permissions are the access control, and a
        `hostPath` of type `Socket` hands it to exactly one pod.
      '';
    };

    adbKeyFile = mkOption {
      type = types.nullOr (types.either types.path types.str);
      default = null;
      description = ''
        sops file holding the adb host private key, exposed to the server
        as ADB_VENDOR_KEYS. With a stable key the phone's "always allow"
        survives a node reinstall; without one adb silently generates a new
        key and the phone shows `unauthorized` until someone taps the
        dialog on its screen.
      '';
    };

    wirelessDebugging = {
      enable = mkEnableOption ''
        re-enabling Android Wireless debugging over USB whenever the device
        appears, and publishing its TLS port for a native scrcpy client
      '';

      portFile = mkOption {
        type = types.str;
        default = "/run/adb/tls-port";
        description = "File that receives `service.adb.tls.port` after each (re)connect.";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    users.groups.${cfg.group} = { };
    users.users.adb = {
      isSystemUser = true;
      inherit (cfg) group;
      home = "/var/lib/adb";
      description = "adb server for the USB-attached Android device";
    };

    # systemd's own 70-uaccess.rules already classifies adb/fastboot USB
    # interfaces (ff/42/01, ff/42/03) as ID_DEBUG_APPLIANCE=android, but the
    # uaccess tag only grants the seated login user — a headless service gets
    # nothing. nixpkgs dropped programs.adb and android-udev-rules for exactly
    # that built-in classification, so the group grant has to live here.
    # Matching the interface class instead of vendor IDs keeps this
    # device-agnostic; the OnePlus 6 enumerates as 2a70, Google devices as 18d1.
    services.udev.extraRules = ''
      SUBSYSTEM=="usb", ENV{ID_DEBUG_APPLIANCE}=="android", GROUP="${cfg.group}", MODE="0660", TAG+="systemd", ENV{SYSTEMD_WANTS}+="adb-server.service"${lib.optionalString cfg.wirelessDebugging.enable ''ENV{SYSTEMD_WANTS}+="adb-wireless-debugging.service"''}
    '';

    sops.secrets."adb-host-key" = mkIf (cfg.adbKeyFile != null) {
      sopsFile = cfg.adbKeyFile;
      format = "binary";
      mode = "0400";
      owner = "adb";
      inherit (cfg) group;
    };

    systemd.services.adb-server = {
      description = "adb server for the USB-attached Android device (Unix socket only)";
      wantedBy = [ "multi-user.target" ];
      environment = {
        HOME = "/var/lib/adb";
      }
      // optionalAttrs (cfg.adbKeyFile != null) {
        ADB_VENDOR_KEYS = config.sops.secrets."adb-host-key".path;
      };
      serviceConfig = {
        # `nodaemon` keeps it in the foreground for systemd; `-L` with a
        # filesystem socket is the documented way to avoid TCP 5037.
        ExecStart = "${adb} -L localfilesystem:${cfg.socketPath} server nodaemon";
        User = "adb";
        Group = cfg.group;
        RuntimeDirectory = "adb";
        RuntimeDirectoryMode = "0750";
        StateDirectory = "adb";
        StateDirectoryMode = "0700";
        UMask = "0007";
        # Any client holding the socket can `adb kill-server`, and a client
        # with a different adb version kills it on sight; always come back.
        Restart = "always";
        RestartSec = 2;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    systemd.services.adb-wireless-debugging = mkIf cfg.wirelessDebugging.enable {
      description = "Re-enable Android Wireless debugging over USB and publish its TLS port";
      after = [ "adb-server.service" ];
      requires = [ "adb-server.service" ];
      environment.ADB_SERVER_SOCKET = "localfilesystem:${cfg.socketPath}";
      path = [ cfg.package ];
      script = ''
        # Android changes the Wireless-debugging port after adbd restarts or a
        # reboot; the native scrcpy client on the daily phone needs the
        # current one. Wait for a booted, authorised device first — `device`
        # alone does not mean the system is up.
        adb wait-for-usb-device
        for _ in $(seq 1 60); do
          [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break
          sleep 2
        done
        adb shell settings put global adb_wifi_enabled 1
        for _ in $(seq 1 30); do
          port="$(adb shell getprop service.adb.tls.port 2>/dev/null | tr -d '\r')"
          if [ -n "$port" ] && [ "$port" != "-1" ]; then
            printf '%s\n' "$port" > ${cfg.wirelessDebugging.portFile}
            exit 0
          fi
          sleep 2
        done
        echo "wireless debugging did not come up" >&2
        exit 1
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "adb";
        Group = cfg.group;
        RuntimeDirectory = "adb";
        RuntimeDirectoryPreserve = true;
      };
    };
  };
}
