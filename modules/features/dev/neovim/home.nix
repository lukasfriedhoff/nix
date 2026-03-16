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
          vimPlugins.plenary-nvim
          vimPlugins.lualine-nvim
          vimPlugins.gitsigns-nvim
          vimPlugins.which-key-nvim
          vimPlugins.nvim-web-devicons
          vimPlugins.nvim-treesitter
          vimPlugins.telescope-nvim
          vimPlugins.nvim-tree-lua
          vimPlugins.mason-nvim
          vimPlugins.mason-lspconfig-nvim
          vimPlugins.nvim-lspconfig
          vimPlugins.nvim-cmp
          vimPlugins.cmp-nvim-lsp
          vimPlugins.luasnip
          vimPlugins.cmp_luasnip
          vimPlugins.tokyonight-nvim
          vimPlugins.nvim-notify
          vimPlugins.nui-nvim
          vimPlugins.ollama-nvim
          (vimPlugins.copilot-lua or null)
          (vimPlugins.CopilotChat-nvim or null)
        ];

        # Tooling injected into PATH for LSP/formatter support.
        extraPackages = with pkgs; [
          ripgrep
          fd
          git
          lazygit
          gcc
          gnumake
          unzip
          nodejs_22
          python3
          lua-language-server
          gopls
          tree-sitter
        ];

        extraLuaConfig = builtins.readFile ./nvim/init.lua;
      };

      home.packages = with pkgs; [
        jq
        bash-language-server
        yaml-language-server
      ];
    })
  ];
}
