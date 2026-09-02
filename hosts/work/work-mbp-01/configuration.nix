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
    # Local llama.cpp server (launchd agent, Metal, router mode).
    lukasf.llamaCppServer.enable = true;

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
        provider.llama-cpp = {
          npm = "@ai-sdk/openai-compatible";
          name = "llama.cpp (local)";
          options.baseURL = "${llamaBaseUrl}/v1";
          models = {
            "qwen3-coder:30b".name = "qwen3-coder:30b";
            "qwen3.8:27b".name = "qwen3.8:27b";
            "qwen3:8b".name = "qwen3:8b";
          };
        };
      };
    };

    programs.dockerHeadless.enable = true;

    # GPU/SoC monitoring (local macmon package; nixpkgs' 0.6.1 panics on M5 Max)
    programs.macmon.enable = true;
  };
}
