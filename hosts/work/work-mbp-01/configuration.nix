_:
let
  llamaBaseUrl = "http://127.0.0.1:11434";
  llamaModel = "qwen3-coder:30b";
in
{
  networking.hostName = "work-mbp-01";

  # Let root fetch the private nix-secrets flake input during
  # `sudo darwin-rebuild switch` (deploy key installed out of band).
  lukasf.nixSecretsAccess.enable = true;

  # Local llama.cpp API for GUI apps (terminal apps get it via home-manager
  # session variables).
  launchd.user.envVariables = {
    OLLAMA_HOST = llamaBaseUrl;
    NVIM_OLLAMA_URL = llamaBaseUrl;
    NVIM_OLLAMA_MODEL = llamaModel;
    NVIM_LLM_BASE_URL = "${llamaBaseUrl}/v1";
    NVIM_LLM_MODEL = llamaModel;
  };

  home-manager.users.lukasfriedhoff = {
    # Local LLM servers, both started on demand (llama-start / mlx-start,
    # see docs/services/local-llm.md).
    lukasf.llamaCppServer = {
      enable = true;
      autoStart = false;
    };
    lukasf.mlxLm.enable = true;

    home.sessionVariables = {
      OLLAMA_HOST = llamaBaseUrl;
      NVIM_OLLAMA_URL = llamaBaseUrl;
      NVIM_OLLAMA_MODEL = llamaModel;
      NVIM_LLM_BASE_URL = "${llamaBaseUrl}/v1";
      NVIM_LLM_MODEL = llamaModel;
      OPENCODE_MODEL = "llama-cpp/${llamaModel}";
    };

    programs.oh-my-opencode = {
      enable = true;
      agentModel = "llama-cpp/${llamaModel}";
    };

    programs.opencode = {
      enable = true;
      settings = {
        model = "llama-cpp/${llamaModel}";
        disabled_providers = [
          "anthropic"
          "openai"
          "github-copilot"
          "google"
          "opencode"
        ];
        provider.mlx = {
          npm = "@ai-sdk/openai-compatible";
          name = "MLX (local)";
          options.baseURL = "http://127.0.0.1:11435/v1";
          models."mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit" = {
            name = "qwen3-coder:30b (mlx)";
            limit = {
              context = 65536;
              output = 8192;
            };
          };
        };
        provider.llama-cpp = {
          npm = "@ai-sdk/openai-compatible";
          name = "llama.cpp (local)";
          options.baseURL = "${llamaBaseUrl}/v1";
          # limit.context must match the llama-server preset window (c in
          # modules/features/llama-cpp-server/home.nix): without it opencode
          # assumes a huge default, never compacts proactively, and requests
          # grow until the server rejects them - the compaction loop.
          models =
            let
              mkModel = name: {
                inherit name;
                limit = {
                  context = 65536;
                  output = 8192;
                };
              };
            in
            {
              "qwen3-coder:30b" = mkModel "qwen3-coder:30b";
              "qwen3.8:27b" = mkModel "qwen3.8:27b";
              "qwen3:8b" = mkModel "qwen3:8b";
            };
        };
      };
    };

    programs.dockerHeadless.enable = true;

    # GPU/SoC monitoring (local macmon package; nixpkgs' 0.6.1 panics on M5 Max)
    programs.macmon.enable = true;

    # Sway-style alt+drag window move/resize
    programs.easyMoveResize.enable = true;

    # Keep-awake menu bar app
    programs.caffeine.enable = true;
  };
}
