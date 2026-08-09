{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.sunshine;

  # Xorg's dummy driver gives Sunshine something to capture when there is no
  # physical output. A container has no seat and no TTY, so GDM cannot start
  # and KMS capture has no CRTC to read — the virtual framebuffer is what makes
  # a headless desktop streamable at all.
  dummyMonitor = ''
    Section "Monitor"
      Identifier "sunshine-dummy"
      HorizSync   ${toString cfg.headless.horizSync}
      VertRefresh ${toString cfg.headless.vertRefresh}
      ${cfg.headless.modeLine}
    EndSection

    Section "Device"
      Identifier "sunshine-dummy-device"
      Driver     "dummy"
      VideoRam   ${toString cfg.headless.videoRamKb}
    EndSection

    Section "Screen"
      Identifier  "sunshine-dummy-screen"
      Device      "sunshine-dummy-device"
      Monitor     "sunshine-dummy"
      DefaultDepth 24
      SubSection "Display"
        Depth     24
        Modes     "${cfg.headless.resolution}"
      EndSubSection
    EndSection
  '';
in
{
  options.lukasf.sunshine = {
    enable = lib.mkEnableOption "Sunshine game/desktop stream host for Moonlight";

    package = lib.mkPackageOption pkgs "sunshine" { };

    openFirewall = lib.mkEnableOption "open the Sunshine stream and web-UI ports";

    vaapiDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/dev/dri/renderD128";
      description = ''
        Render node used for hardware encoding. Null lets Sunshine pick.

        The node must be passed into the container; the userspace VAAPI driver
        comes from this image's mesa, not from the host, which is why a server
        host without a graphics stack can still back a streaming container.
      '';
    };

    headless = {
      enable = lib.mkEnableOption "an Xorg dummy virtual display for headless capture" // {
        default = true;
      };

      resolution = lib.mkOption {
        type = lib.types.str;
        default = "1920x1080";
        description = "Virtual display resolution.";
      };

      modeLine = lib.mkOption {
        type = lib.types.str;
        default = ''Modeline "1920x1080" 148.50 1920 2448 2492 2640 1080 1084 1089 1125 +hsync +vsync'';
        description = "Modeline matching {option}`resolution`.";
      };

      horizSync = lib.mkOption {
        type = lib.types.str;
        default = "5.0 - 200.0";
        description = "Dummy monitor horizontal sync range, in kHz.";
      };

      vertRefresh = lib.mkOption {
        type = lib.types.str;
        default = "5.0 - 200.0";
        description = "Dummy monitor vertical refresh range, in Hz.";
      };

      videoRamKb = lib.mkOption {
        type = lib.types.int;
        default = 256000;
        description = ''
          Dummy driver framebuffer size in KB. Must exceed
          width * height * 4; 256 MB comfortably covers 4K.
        '';
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "lukasf";
        description = "User automatically logged in to own the streamed session.";
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Extra settings merged into {option}`services.sunshine.settings`.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        services.sunshine = {
          enable = true;
          inherit (cfg) package;
          inherit (cfg) openFirewall;
          # DRM/KMS capture needs CAP_SYS_ADMIN. Harmless with the dummy driver
          # and required the moment a real output is used instead.
          capSysAdmin = lib.mkDefault true;
          settings = lib.mkMerge [
            (lib.mkIf (cfg.vaapiDevice != null) { adapter_name = cfg.vaapiDevice; })
            cfg.settings
          ];
        };

        # Sunshine synthesises keyboard/mouse input through uinput; without the
        # node and group the stream connects but stays read-only.
        boot.kernelModules = [ "uinput" ];
        hardware.uinput.enable = lib.mkDefault true;
        users.users.${cfg.headless.user}.extraGroups = lib.mkAfter [
          "input"
          "video"
          "render"
        ];

        # mesa in the image is what provides radeonsi/iHD; the render node alone
        # is not enough for VAAPI to initialise.
        hardware.graphics.enable = lib.mkDefault true;

        assertions = [
          {
            assertion = cfg.vaapiDevice == null || lib.hasPrefix "/dev/dri/" cfg.vaapiDevice;
            message = "lukasf.sunshine.vaapiDevice must be a /dev/dri render node.";
          }
        ];
      }

      (lib.mkIf cfg.headless.enable {
        services.xserver = {
          enable = lib.mkDefault true;
          videoDrivers = lib.mkDefault [ "dummy" ];
          extraConfig = dummyMonitor;
        };

        # GDM expects a seat and a TTY, neither of which exists in a container.
        # Autologin straight into the session so Sunshine's user service has a
        # display to attach to.
        services.displayManager = {
          gdm.enable = lib.mkForce false;
          autoLogin = {
            enable = lib.mkDefault true;
            user = lib.mkDefault cfg.headless.user;
          };
        };
      })
    ]
  );
}
