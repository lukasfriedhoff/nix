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

          # AI integration (ollama + opencode only)
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
          fd
          git
          lazygit
          gcc
          gnumake
          unzip
          tree-sitter

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
          nodePackages.typescript-language-server
          nodePackages.eslint
          nodePackages.prettier

          # Bash
          bash-language-server
          shellcheck
          shfmt

          # YAML/JSON
          yaml-language-server
          nodePackages.vscode-json-languageserver

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

        extraLuaConfig = builtins.readFile ./nvim/init.lua;
      };

      home.packages = with pkgs; [
        jq
      ];
    })
  ];
}
