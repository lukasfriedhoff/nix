_: {
  networking.hostName = "macbook-pro";

  # Let root fetch the private nix-secrets flake input during
  # `sudo darwin-rebuild switch` (deploy key installed out of band).
  lukasf.nixSecretsAccess.enable = true;

  # Make the remote OpenAI-compatible LLM API available to GUI and terminal apps.
  launchd.user.envVariables = {
    OLLAMA_HOST = "http://10.7.5.19:11434";
    NVIM_OLLAMA_URL = "http://10.7.5.19:11434";
    NVIM_OLLAMA_MODEL = "qwen3-coder:30b";
    NVIM_LLM_BASE_URL = "http://10.7.5.19:11434/v1";
    NVIM_LLM_MODEL = "qwen3-coder:30b";
  };

  # Work desktop: install and configure OpenCode against the remote Ollama host.
  home-manager.users.lukasfriedhoff = {
    home.sessionVariables = {
      OLLAMA_HOST = "http://10.7.5.19:11434";
      NVIM_OLLAMA_URL = "http://10.7.5.19:11434";
      NVIM_OLLAMA_MODEL = "qwen3-coder:30b";
      NVIM_LLM_BASE_URL = "http://10.7.5.19:11434/v1";
      NVIM_LLM_MODEL = "qwen3-coder:30b";
      OPENCODE_MODEL = "ollama/qwen3-coder:30b";
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

    programs.opencode = {
      enable = true;
      settings = {
        model = "ollama/qwen3-coder:30b";
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
          options.baseURL = "http://10.7.5.19:11434/v1";
          models."qwen3-coder:30b".name = "qwen3-coder:30b";
        };
      };
    };

    programs.dockerHeadless.enable = true;
  };

  # host-specific homebrew casks
  homebrew.casks = [
    "aerospace"
  ];

  # SketchyBar via homebrew tap
  homebrew.taps = [
    "FelixKratz/formulae"
  ];
  homebrew.brews = [
    "sketchybar"
  ];
}
