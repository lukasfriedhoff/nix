{
  config,
  inputs,
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
  llmOllamaHostByProfile = {
    # srv4 hosts the local LLM runtime directly.
    srv4 = "http://127.0.0.1:11434";
    # Other personal desktops consume srv4 as shared backend.
    tux = "http://srv4.lab.h4xx.io:11434";
    tab = "http://srv4.lab.h4xx.io:11434";
    lenovo = "http://srv4.lab.h4xx.io:11434";
  };
  llmOpenWebUiByProfile = {
    srv4 = "http://127.0.0.1:3000";
    tux = "http://srv4.lab.h4xx.io:3000";
    tab = "http://srv4.lab.h4xx.io:3000";
    lenovo = "http://srv4.lab.h4xx.io:3000";
  };
  defaultOllamaHost = "http://srv4.lab.h4xx.io:11434";
  defaultOpenWebUiUrl = "http://srv4.lab.h4xx.io:3000";
  resolvedOllamaHost =
    if profile != null && builtins.hasAttr profile llmOllamaHostByProfile then
      llmOllamaHostByProfile.${profile}
    else
      defaultOllamaHost;
  resolvedOpenWebUiUrl =
    if profile != null && builtins.hasAttr profile llmOpenWebUiByProfile then
      llmOpenWebUiByProfile.${profile}
    else
      defaultOpenWebUiUrl;
  isPersonalDesktop = profile != null && lib.elem profile personalDesktopProfiles;
  isLinuxDesktop = isPersonalDesktop && (!pkgs.stdenv.isDarwin);
  isPersonalWorkstation = profile != null && lib.elem profile personalWorkstationProfiles;
  isLinuxWorkstation = isPersonalWorkstation && (!pkgs.stdenv.isDarwin);
in
{
  config = lib.mkMerge [
    (lib.mkIf isLinuxDesktop {
      programs.bash.shellAliases = {
        scrcpy = "env -u DRI_PRIME -u __NV_PRIME_RENDER_OFFLOAD SDL_VIDEODRIVER=x11 scrcpy --render-driver=opengl --video-codec=h264";
      };

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

      home.packages = [
        pkgs.gpodder
        pkgs.cloudflared
        pkgs.noto-fonts-color-emoji
        pkgs.font-awesome
        pkgs.nerd-fonts.symbols-only
        inputs.witr.packages.${pkgs.system}.default
      ];

      home.sessionVariables = {
        OLLAMA_HOST = resolvedOllamaHost;
        NVIM_OLLAMA_URL = resolvedOllamaHost;
        NVIM_OLLAMA_MODEL = "qwen3-coder:30b";
        OPENWEBUI_URL = resolvedOpenWebUiUrl;
      };

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

      dconf.settings."org/gnome/desktop/wm/keybindings" = {
        "switch-windows" = [ "<Alt>Tab" ];
        "switch-windows-backward" = [ "<Shift><Alt>Tab" ];
        "switch-applications" = [ ];
        "switch-applications-backward" = [ ];
        "switch-input-source" = [ "<Control>space" ];
        "switch-input-source-backward" = [ "<Shift><Control>space" ];
      };

      dconf.settings."org/gnome/desktop/input-sources" = {
        "xkb-options" = [ "grp:ctrl_space_toggle" ];
      };

      # Prevent immediate re-suspend after long idle periods across sleep/resume cycles.
      dconf.settings."org/gnome/settings-daemon/plugins/power" = {
        "sleep-inactive-ac-type" = "nothing";
        "sleep-inactive-battery-type" = "nothing";
        "idle-dim" = false;
      };

      # Keep displays from dimming/blanking while idle.
      dconf.settings."org/gnome/desktop/session" = {
        "idle-delay" = lib.hm.gvariant.mkUint32 0;
      };
    })
    (lib.mkIf isLinuxWorkstation {
      programs.bash.shellAliases = {
        llm-srv4-start = "ssh srv4 'sudo systemctl start ollama-podman.service open-webui-podman.service'";
        llm-srv4-stop = "ssh srv4 'sudo systemctl stop ollama-podman.service open-webui-podman.service'";
        llm-srv4-status = "ssh srv4 'systemctl status --no-pager ollama-podman.service open-webui-podman.service'";
      };

      home.packages = lib.mkAfter [
        pkgs.podman
        pkgs.btop
      ];

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
    })
  ];
}
