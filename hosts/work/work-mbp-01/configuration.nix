{
  config,
  secrets,
  ...
}:
let
  llamaBaseUrl = "http://127.0.0.1:11434";
  # llama.cpp preset used by the neovim/Ollama-style env (port 11434).
  llamaModel = "qwen3.8:27b";
  # Default for opencode and its agents. llama.cpp is the only runtime here:
  # MLX was dropped (nixpkgs build is CPU-only; the Metal PyPI build has no
  # memory guard and panicked the machine with a 27B under a real prompt).
  defaultOpencodeModel = "llama-cpp/${llamaModel}";
in
{
  networking.hostName = "work-mbp-01";

  # Let root fetch the private nix-secrets flake input during
  # `sudo darwin-rebuild switch` (deploy key installed out of band).
  lukasf.nixSecretsAccess.enable = true;

  # Hugging Face token for model downloads (anonymous pulls are throttled).
  # Decrypted by sops-nix at activation; the user-level LLM servers read it.
  sops.age.keyFile = "/Users/lukasfriedhoff/.config/sops/age/keys.txt";
  sops.secrets.hf-token = {
    sopsFile = "${secrets.primary}/hf-token.txt";
    format = "binary";
    owner = "lukasfriedhoff";
    mode = "0400";
  };

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
    # Local llama.cpp server, started on demand (llama-start, see
    # docs/services/local-llm.md).
    lukasf.llamaCppServer = {
      enable = true;
      autoStart = false;
      defaultModel = llamaModel;
      hfTokenFile = config.sops.secrets.hf-token.path;
    };

    # Expose the local llama.cpp server on tux via a reverse tunnel (mac
    # initiates; tux then reaches it as localhost:11434). Requires llama-start.
    # tux has no stable address, so the target is an argument (default: mDNS);
    # -o Hostname overrides only the address while the `tux` ssh alias keeps
    # supplying user and tunnel key.
    programs.bash.initExtra = ''
      llama-share-tux() {
        local host="''${1:-tux-h4xx-01.local}"
        echo "reverse tunnel: ''${host} -> localhost:11434 (ctrl+c stops it)" >&2
        ssh -N -o ExitOnForwardFailure=yes -o "Hostname=''${host}" \
          -R 127.0.0.1:11434:127.0.0.1:11434 tux
      }
    '';

    home.sessionVariables = {
      OLLAMA_HOST = llamaBaseUrl;
      NVIM_OLLAMA_URL = llamaBaseUrl;
      NVIM_OLLAMA_MODEL = llamaModel;
      NVIM_LLM_BASE_URL = "${llamaBaseUrl}/v1";
      NVIM_LLM_MODEL = llamaModel;
      OPENCODE_MODEL = defaultOpencodeModel;
    };

    programs.oh-my-opencode = {
      enable = true;
      agentModel = defaultOpencodeModel;
    };

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
    # Start the Docker VM on demand (docker-start), not at login; see
    # docs/services/docker-colima.md.
    programs.dockerHeadless.startAtLogin = false;

    # GPU/SoC monitoring (local macmon package; nixpkgs' 0.6.1 panics on M5 Max)
    programs.macmon.enable = true;

    # Keep-awake menu bar app
    programs.caffeine.enable = true;
  };
}
