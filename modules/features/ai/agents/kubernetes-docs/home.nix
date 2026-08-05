{
  config,
  lib,
  ...
}:

let
  cfg = config.ai.agents.kubernetesDocs;
in
{
  options.ai.agents.kubernetesDocs = {
    enable = lib.mkEnableOption "Kubernetes documentation research agent";
  };

  config = lib.mkIf cfg.enable {
    # Install agent for both Claude and OpenCode
    home.file.".claude/agents/kubernetes-docs.md".source = ./kubernetes-docs.md;
    home.file.".opencode/agents/kubernetes-docs.md".source = ./kubernetes-docs.md;

    lukasf.claude.defaultAllowList = [
      "WebFetch(domain:kubernetes.io)"
      "WebFetch(domain:k8s.io)"
      "WebFetch(domain:helm.sh)"
      "WebFetch(domain:fluxcd.io)"
      "WebFetch(domain:docs.cilium.io)"
      "WebFetch(domain:cert-manager.io)"
      "WebFetch(domain:kustomize.io)"
    ];
  };
}
