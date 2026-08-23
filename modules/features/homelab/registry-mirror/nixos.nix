# Points containerd at the in-cluster Forgejo registry over the LAN path
# (ClusterIP), so image pulls for cluster-hosted packages never cross the
# Cloudflare tunnel. Nodes authenticate with a read-only package token.
{
  config,
  lib,
  secrets ? { },
  ...
}:
let
  k8s = config.homelab.kubernetes;
  cfg = config.homelab.forgejoRegistryMirror;
in
{
  options.homelab.forgejoRegistryMirror = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = k8s.enable && k8s.distribution == "k3s";
      defaultText = "true on k3s nodes";
      description = "Mirror the Forgejo registry host to its cluster-internal endpoint.";
    };
    registryHost = lib.mkOption {
      type = lib.types.str;
      default = "forgejo.h4xx.io";
      description = "Registry host as referenced in image names.";
    };
    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://10.43.4.217:3000";
      description = "Cluster-internal Forgejo HTTP endpoint (stable ClusterIP).";
    };
    username = lib.mkOption {
      type = lib.types.str;
      default = "lukasf";
      description = "Forgejo user owning the read-only package token.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."forgejo-registry-pull-token" = {
      sopsFile = "${secrets.profileShared}/forgejo/registry-pull-token.txt";
      format = "binary";
    };

    sops.templates."k3s-registries.yaml" = {
      path = "/etc/rancher/k3s/registries.yaml";
      content = ''
        mirrors:
          "${cfg.registryHost}":
            endpoint:
              - "${cfg.endpoint}"
        configs:
          "${cfg.registryHost}":
            auth:
              username: ${cfg.username}
              password: ${config.sops.placeholder."forgejo-registry-pull-token"}
      '';
    };

    # containerd only reads registries.yaml at startup.
    systemd.services.k3s.restartTriggers = [
      config.sops.templates."k3s-registries.yaml".content
    ];
  };
}
