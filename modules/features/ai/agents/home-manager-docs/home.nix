{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.agents.homeManagerDocs;
in
{
  options.ai.agents.homeManagerDocs = {
    enable = lib.mkEnableOption "Home Manager documentation research agent";
  };

  config = lib.mkIf cfg.enable {
    # Install agent for both Claude and OpenCode
    home.file.".claude/agents/home-manager-docs.md".source = ./home-manager-docs.md;
    home.file.".opencode/agents/home-manager-docs.md".source = ./home-manager-docs.md;

    lukasf.claude.defaultAllowList = [
      "WebFetch(domain:home-manager-options.extranix.com)"
      "WebFetch(domain:nix-community.github.io)"
      "WebFetch(domain:github.com)"
    ];
  };
}
