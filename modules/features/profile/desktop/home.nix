# Desktop profile for personal Linux workstations
# Enables GUI applications, development tools, and AI assistants
{
  config,
  inputs,
  lib,
  pkgs,
  profile ? null,
  ...
}:

let
  # Use profile-based detection for backwards compatibility
  personalDesktopProfiles = [
    "srv4"
    "tux"
    "tab"
    "lenovo"
  ];
  isPersonalDesktop = profile != null && lib.elem profile personalDesktopProfiles;

  # Check profiles.desktop.enable if defined, otherwise fall back to profile detection
  desktopEnabled =
    if config ? profiles && config.profiles ? desktop then
      config.profiles.desktop.enable
    else
      isPersonalDesktop;

  # Workstation profiles get extra development tools
  personalWorkstationProfiles = [
    "tux"
    "lenovo"
  ];

  # LLM backend configuration per profile
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
  defaultOpencodeModel = "ollama/qwen3-coder:30b";
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
  resolvedOpencodeBaseUrl = "${lib.removeSuffix "/" resolvedOllamaHost}/v1";

  isLinuxDesktop = desktopEnabled && (!pkgs.stdenv.isDarwin);
  isPersonalWorkstation = profile != null && lib.elem profile personalWorkstationProfiles;
  isLinuxWorkstation = isPersonalWorkstation && (!pkgs.stdenv.isDarwin);
in
{
  config = lib.mkMerge [
    (lib.mkIf isLinuxDesktop {
      programs.kubeconfig = lib.mkIf isPersonalDesktop {
        enable = lib.mkDefault true;
        defaultContext = lib.mkDefault "homelab-prod";
        clusters = lib.mkDefault [
          {
            name = "homelab-prod";
            mode = "ssh";
            sshHost = "srv1";
            apiServer = "https://srv1.lab.h4xx.io:6443";
            contextName = "homelab-prod";
          }
          {
            name = "homelab-testing";
            mode = "ssh";
            sshHost = "srv3";
            apiServer = "https://srv3.lab.h4xx.io:6443";
            contextName = "homelab-testing";
          }
          {
            name = "homelab-staging";
            mode = "ssh";
            sshHost = "srv5-k3s-stg1";
            apiServer = "https://srv5-k3s-stg1.lab.h4xx.io:6443";
            contextName = "homelab-staging";
          }
        ];
      };

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
        inputs.witr.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];

      home.sessionVariables = {
        OLLAMA_HOST = resolvedOllamaHost;
        NVIM_OLLAMA_URL = resolvedOllamaHost;
        NVIM_OLLAMA_MODEL = "qwen3-coder:30b";
        OPENCODE_MODEL = defaultOpencodeModel;
        OPENWEBUI_URL = resolvedOpenWebUiUrl;
        # Required for opencode plugins with native node modules (onnxruntime, etc.)
        LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
      };

      # Enable Nix-managed AI agents and skills (uses config.profiles.desktop from core)
      ai.enable = lib.mkDefault true;

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

      # Declarative opencode configuration (uses built-in Home Manager module)
      programs.opencode = {
        enable = true;
        settings = {
          model = defaultOpencodeModel;
          disabled_providers = [
            "anthropic"
            "openai"
            "github-copilot"
            "google"
            "opencode"
          ];
          provider.ollama = {
            npm = "@ai-sdk/openai-compatible";
            name = "Ollama";
            options.baseURL = resolvedOpencodeBaseUrl;
            models."qwen3-coder:30b".name = "qwen3-coder:30b";
          };
          agent = {
            explore.skills = [
              "flake"
              "flux"
              "git-master"
              "helm"
              "home-manager"
              "kubernetes"
              "neovim-config"
              "nix"
              "sops-secrets"
              "ssh"
              "wireguard"
            ];
            build.skills = [
              "cert-manager"
              "cilium"
              "flake"
              "flux"
              "git-master"
              "helm"
              "home-manager"
              "kubernetes"
              "kustomize"
              "neovim-config"
              "nix"
              "podman"
              "sops-secrets"
              "ssh"
              "systemd"
              "wireguard"
            ];
            plan.skills = [
              "flake"
              "flux"
              "git-master"
              "home-manager"
              "kubernetes"
              "neovim-config"
              "nix"
            ];
          };
        };
        # Skills are managed by lukasf.ai module and installed to ~/.opencode/skills/
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
