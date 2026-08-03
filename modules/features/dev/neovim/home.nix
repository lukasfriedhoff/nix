{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (pkgs) vimPlugins;
  cfg = config.programs.neovim;
in
{
  config = lib.mkMerge [
    {
      programs.neovim.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      programs.neovim = {
        vimAlias = true;
        withNodeJs = true;
        withPython3 = true;
        withRuby = false; # Explicitly adopt new default (was true before 26.05)

        # Plugin set kept minimal but batteries-included for daily development.
        plugins = lib.filter (p: p != null) [
          # Core utilities
          vimPlugins.plenary-nvim
          vimPlugins.nui-nvim
          vimPlugins.nvim-web-devicons

          # UI
          vimPlugins.lualine-nvim
          vimPlugins.tokyonight-nvim
          vimPlugins.nvim-notify
          vimPlugins.snacks-nvim

          # Navigation & search
          vimPlugins.telescope-nvim
          vimPlugins.nvim-tree-lua
          vimPlugins.which-key-nvim

          # Git
          vimPlugins.gitsigns-nvim
          vimPlugins.lazygit-nvim

          # Treesitter
          vimPlugins.nvim-treesitter
          vimPlugins.nvim-treesitter-textobjects

          # LSP & completion
          vimPlugins.mason-nvim
          vimPlugins.mason-lspconfig-nvim
          vimPlugins.nvim-lspconfig
          vimPlugins.nvim-cmp
          vimPlugins.cmp-nvim-lsp
          vimPlugins.cmp-buffer
          vimPlugins.cmp-path
          vimPlugins.luasnip
          vimPlugins.cmp_luasnip
          vimPlugins.friendly-snippets

          # Linting & formatting
          vimPlugins.none-ls-nvim
          vimPlugins.conform-nvim

          # AI integration (local Ollama/llama.cpp + opencode)
          vimPlugins.ollama-nvim
          vimPlugins.opencode-nvim

          # Kubernetes
          (vimPlugins.vim-kubernetes or null)
          (vimPlugins.helm-vim or null)
        ];

        # Tooling injected into PATH for LSP/formatter support.
        extraPackages = with pkgs; [
          # Core tools
          ripgrep
          curl
          fd
          git
          lazygit
          gcc
          gnumake
          unzip
          tree-sitter
          opencode

          # Language runtimes
          nodejs_22
          python3
          go

          # Lua
          lua-language-server
          stylua

          # Go
          gopls
          golangci-lint
          gotools
          delve

          # Python
          pyright
          ruff
          black

          # JavaScript/TypeScript
          typescript-language-server
          eslint
          prettier

          # Bash
          bash-language-server
          shellcheck
          shfmt

          # YAML/JSON
          yaml-language-server
          vscode-langservers-extracted # provides vscode-json-languageserver

          # C/C++
          clang-tools
          lldb

          # Terraform
          terraform-ls
          tflint

          # Ansible (ansible-language-server removed from nixpkgs)
          ansible-lint

          # Kubernetes/Flux
          kubectl
          kubernetes-helm
          fluxcd
          kustomize
          k9s
          helm-ls
        ];

        initLua = builtins.readFile ./nvim/init.lua;
      };

      home.packages = with pkgs; [
        jq
      ];
    })
  ];
}
