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
  # Single source of truth lives in profile/core/home.nix.
  desktopEnabled = config.profiles.desktop.enable;

  # Workstation profiles get extra development tools
  personalWorkstationProfiles = [
    "tux"
    "lenovo"
  ];

  # LLM backend configuration per profile. srv4 runs llama.cpp on the
  # historical Ollama port so existing network paths stay stable.
  llmApiBaseUrlByProfile = {
    srv4 = "http://127.0.0.1:11434/v1";
    tux = "http://srv4.lab.h4xx.io:11434/v1";
    tab = "http://srv4.lab.h4xx.io:11434/v1";
    lenovo = "http://srv4.lab.h4xx.io:11434/v1";
  };
  llmOpenWebUiByProfile = {
    srv4 = "http://127.0.0.1:3000";
    tux = "http://srv4.lab.h4xx.io:3000";
    tab = "http://srv4.lab.h4xx.io:3000";
    lenovo = "http://srv4.lab.h4xx.io:3000";
  };
  defaultLlmApiBaseUrl = "http://srv4.lab.h4xx.io:11434/v1";
  defaultOpenWebUiUrl = "http://srv4.lab.h4xx.io:3000";
  defaultLlmModel = "qwen3:8b";
  defaultOpencodeLlmModel = defaultLlmModel;
  defaultOpencodeModel = "llama-cpp/${defaultOpencodeLlmModel}";
  kimiApiModel = "kimi-k3";
  favoriteLlmModels = [
    "qwen3:8b"
    "qwen3-coder:30b"
    "qwen3-coder:30b-quality"
    "qwen3:30b"
    "qwen3.8:27b"
    "qwen3-coder-next"
  ];
  kimiApiModels = [
    kimiApiModel
    "kimi-k2.7-code"
    "kimi-k2.7-code-highspeed"
  ];
  resolvedLlmApiBaseUrl =
    if profile != null && builtins.hasAttr profile llmApiBaseUrlByProfile then
      llmApiBaseUrlByProfile.${profile}
    else
      defaultLlmApiBaseUrl;
  resolvedOpenWebUiUrl =
    if profile != null && builtins.hasAttr profile llmOpenWebUiByProfile then
      llmOpenWebUiByProfile.${profile}
    else
      defaultOpenWebUiUrl;
  resolvedLlamaCppHost = lib.removeSuffix "/v1" (lib.removeSuffix "/" resolvedLlmApiBaseUrl);

  isLinuxDesktop = desktopEnabled && (!pkgs.stdenv.isDarwin);
  isPersonalWorkstation = profile != null && lib.elem profile personalWorkstationProfiles;
  isLinuxWorkstation = isPersonalWorkstation && (!pkgs.stdenv.isDarwin);
in
{
  config = lib.mkMerge [
    (lib.mkIf isLinuxDesktop {
      programs.kubeconfig = {
        enable = lib.mkDefault true;
        defaultContext = lib.mkDefault "homelab-prod";
        clusters = lib.mkDefault [
          {
            name = "homelab-prod";
            mode = "ssh";
            sshHost = "srv2";
            apiServer = "https://srv2.lab.h4xx.io:6443";
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

      # zathura for PDFs (vim-keys document viewer); feh for images.
      # feh has no PDF backend, so PDFs deliberately do not point at it.
      programs.zathura.enable = lib.mkDefault true;
      programs.feh.enable = lib.mkDefault true;

      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "application/pdf" = [ "org.pwmt.zathura.desktop" ];
          "image/jpeg" = [ "feh.desktop" ];
          "image/png" = [ "feh.desktop" ];
          "image/gif" = [ "feh.desktop" ];
          "image/webp" = [ "feh.desktop" ];
          "image/bmp" = [ "feh.desktop" ];
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
        pkgs.go
        pkgs.gopls
        pkgs.gcc
        pkgs.jameica
        pkgs.masterpdfeditorLicenseCompatible
        pkgs.nodejs_22
        pkgs.noto-fonts-color-emoji
        pkgs.font-awesome
        pkgs.nerd-fonts.symbols-only
        inputs.witr.packages.${pkgs.stdenv.hostPlatform.system}.default
      ];

      home.sessionVariables = {
        LLAMA_CPP_HOST = resolvedLlamaCppHost;
        LLAMA_CPP_BASE_URL = resolvedLlmApiBaseUrl;
        NVIM_LLM_BASE_URL = resolvedLlmApiBaseUrl;
        NVIM_LLM_MODEL = defaultLlmModel;
        NVIM_LLM_MODELS = lib.concatStringsSep "," favoriteLlmModels;
        OPENCODE_MODEL = defaultOpencodeModel;
        OPENCODE_KIMI_API_MODEL = "kimi-api/${kimiApiModel}";
        OPENWEBUI_URL = resolvedOpenWebUiUrl;
      }
      // lib.optionalAttrs config.profiles.desktop.nixLd.enable {
        # Required for opencode plugins with native node modules (onnxruntime, etc.)
        # Only meaningful on NixOS hosts with nix-ld; see profiles.desktop.nixLd.
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
          provider."llama-cpp" = {
            npm = "@ai-sdk/openai-compatible";
            name = "llama.cpp";
            options.baseURL = resolvedLlmApiBaseUrl;
            models = builtins.listToAttrs (
              map (model: {
                name = model;
                value.name = model;
              }) favoriteLlmModels
            );
          };
          provider."kimi-api" = {
            npm = "@ai-sdk/openai-compatible";
            name = "Kimi API";
            api = "https://api.moonshot.cn/v1";
            env = [ "MOONSHOT_API_KEY" ];
            options.apiKey = "{env:MOONSHOT_API_KEY}";
            models = builtins.listToAttrs (
              map (model: {
                name = model;
                value.name = model;
              }) kimiApiModels
            );
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
        llm-srv4-models = "ssh srv4 'curl -fsS http://127.0.0.1:11434/v1/models'";
        opencode-qwen3-coder = "OPENCODE_MODEL=llama-cpp/qwen3-coder:30b opencode";
        opencode-kimi-api = "OPENCODE_MODEL=kimi-api/${kimiApiModel} opencode";
      };

      home.packages = lib.mkAfter [
        pkgs.podman
        pkgs.btop
      ];

      programs.icarusModManager = {
        enable = true;
      };
    })
  ];
}
