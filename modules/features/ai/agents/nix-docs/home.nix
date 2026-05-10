{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.agents.nixDocs;
in
{
  options.ai.agents.nixDocs = {
    enable = lib.mkEnableOption "Nix documentation research agent";
  };

  config = lib.mkIf cfg.enable {
    # Install agent for both Claude and OpenCode
    home.file.".claude/agents/nix-docs.md".source = ./nix-docs.md;
    home.file.".opencode/agents/nix-docs.md".source = ./nix-docs.md;

    # Add permissions for Claude to fetch Nix documentation sites
    programs.claude-code.settings.permissions.allow = [
      "WebFetch(domain:nixos.org)"
      "WebFetch(domain:nix.dev)"
      "WebFetch(domain:wiki.nixos.org)"
      "WebFetch(domain:home-manager-options.extranix.com)"
      "WebFetch(domain:search.nixos.org)"
      "WebFetch(domain:noogle.dev)"
    ];
  };
}
