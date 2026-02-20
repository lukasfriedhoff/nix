{
  config,
  lib,
  pkgs,
  profile ? null,
  ...
}:

let
  personalDesktopProfiles = [
    "srv4"
    "tux"
    "tab"
    "lenovo"
  ];
  personalWorkstationProfiles = [
    "tux"
    "lenovo"
  ];
  isPersonalDesktop = profile != null && lib.elem profile personalDesktopProfiles;
  isLinuxDesktop = isPersonalDesktop && (!pkgs.stdenv.isDarwin);
  isPersonalWorkstation = profile != null && lib.elem profile personalWorkstationProfiles;
  isLinuxWorkstation = isPersonalWorkstation && (!pkgs.stdenv.isDarwin);
in
{
  config = lib.mkMerge [
    (lib.mkIf isLinuxDesktop {
      programs.evolution.enable = lib.mkDefault true;
      programs.evolution.nextcloud.enable = lib.mkDefault true;

      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "text/html" = [ "firefox.desktop" ];
          "x-scheme-handler/http" = [ "firefox.desktop" ];
          "x-scheme-handler/https" = [ "firefox.desktop" ];
          "x-scheme-handler/about" = [ "firefox.desktop" ];
          "x-scheme-handler/unknown" = [ "firefox.desktop" ];
          "x-scheme-handler/mailto" = [ "org.gnome.Evolution.desktop" ];
          "message/rfc822" = [ "org.gnome.Evolution.desktop" ];
        };
      };

      programs.moonlight.enable = lib.mkDefault true;

      home.packages = [ pkgs.gpodder ];
    })
    (lib.mkIf isLinuxWorkstation {
      home.sessionVariables = {
        OLLAMA_HOST = "http://srv1.lab.h4xx.io:11434";
      };

      home.packages = lib.mkAfter [
        pkgs.podman
        pkgs.btop
      ];

      programs.oh-my-opencode = {
        enable = true;
        subscriptions = {
          claude = "no";
          openai = "no";
          gemini = "no";
          copilot = "no";
          opencodeZen = "no";
          zaiCodingPlan = "no";
        };
      };

      # Remove old OpenAI API key file; prefer ChatGPT Plus, Gemini Pro, and Copilot sign-ins.
      home.activation.decryptOpenAIEnv = lib.mkForce (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          rm -f "${config.xdg.configHome}/secrets/openai.env"
        ''
      );

      programs.icarusModManager = {
        enable = true;
        autoInstallDotnet80 = true;
      };

      dconf.settings."org/gnome/desktop/wm/keybindings" = {
        "switch-windows" = [ "<Alt>Tab" ];
        "switch-windows-backward" = [ "<Shift><Alt>Tab" ];
        "switch-applications" = [ ];
        "switch-applications-backward" = [ ];
      };
    })
  ];
}
