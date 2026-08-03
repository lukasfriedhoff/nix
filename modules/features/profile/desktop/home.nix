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
  defaultAirLlmApiBaseUrl = "http://127.0.0.1:11435/v1";
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
  ];
  airLlmModels = [
    kimiApiModel
    "qwen3:30b-airllm"
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

  masterpdfeditorLicenseCompatible = pkgs.masterpdfeditor.overrideAttrs (_old: {
    version = "5.9.60";
    src = pkgs.fetchurl {
      url = "https://code-industry.net/public/master-pdf-editor-5.9.60-qt5.x86_64.tar.gz";
      hash = "sha256-KnqqoPhpcQA3mFuuGlZO6RyONgbKFDojDFz+hYFfq9c=";
    };

    installPhase = ''
      runHook preInstall

      substituteInPlace masterpdfeditor5.desktop \
        --replace-fail "Exec=/opt/master-pdf-editor-5/masterpdfeditor5" "Exec=masterpdfeditor5" \
        --replace-fail "Path=/opt/master-pdf-editor-5" "Path=$out/share/masterpdfeditor" \
        --replace-fail "/opt/master-pdf-editor-5/masterpdfeditor5.png" "masterpdfeditor5"

      install -Dm644 masterpdfeditor5.desktop -t $out/share/applications
      install -Dm644 masterpdfeditor5.png -t $out/share/icons/hicolor/128x128/apps
      install -Dm755 masterpdfeditor5 -t $out/share/masterpdfeditor
      cp -r stamps templates lang fonts $out/share/masterpdfeditor

      mkdir -p $out/bin
      ln -s $out/share/masterpdfeditor/masterpdfeditor5 $out/bin/masterpdfeditor5

      runHook postInstall
    '';
  });
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
        pkgs.go
        pkgs.gopls
        pkgs.gcc
        pkgs.jameica
        masterpdfeditorLicenseCompatible
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
        OPENCODE_AIRLLM_MODEL = "airllm-srv4/${kimiApiModel}";
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
          provider."airllm-srv4" = {
            npm = "@ai-sdk/openai-compatible";
            name = "srv4 AirLLM";
            options.baseURL = defaultAirLlmApiBaseUrl;
            models = builtins.listToAttrs (
              map (model: {
                name = model;
                value.name = model;
              }) airLlmModels
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
        llm-srv4-start = "ssh srv4 'sudo systemctl start llama-cpp-podman.service open-webui-podman.service'";
        llm-srv4-stop = "ssh srv4 'sudo systemctl stop llama-cpp-podman.service open-webui-podman.service'";
        llm-srv4-status = "ssh srv4 'systemctl status --no-pager llama-cpp-podman.service open-webui-podman.service'";
        llm-srv4-models = "ssh srv4 'curl -fsS http://127.0.0.1:11434/v1/models'";
        airllm-srv4-tunnel = "ssh -NT -o ExitOnForwardFailure=yes -L 127.0.0.1:11435:127.0.0.1:11435 srv4";
        opencode-qwen3-coder = "OPENCODE_MODEL=llama-cpp/qwen3-coder:30b opencode";
        opencode-kimi-api = "OPENCODE_MODEL=kimi-api/${kimiApiModel} opencode";
        opencode-airllm = "OPENCODE_MODEL=airllm-srv4/${kimiApiModel} opencode";
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
      };
    })
  ];
}
