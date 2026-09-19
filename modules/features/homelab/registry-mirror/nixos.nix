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

    pullThrough = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = k8s.enable && k8s.distribution == "k3s";
        defaultText = "true on k3s nodes";
        description = "Route public-registry pulls through Harbor's proxy-cache projects. containerd tries mirror endpoints in order and always falls back to the original registry, so an unreachable Harbor only costs latency, never availability.";
      };
      harborHost = lib.mkOption {
        type = lib.types.str;
        default = "harbor.h4xx.io";
        description = "Harbor host (LAN split-horizon resolves it past the Cloudflare tunnel).";
      };
      mirrors = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {
          "docker.io" = "proxy-docker";
          "ghcr.io" = "proxy-ghcr";
          "quay.io" = "proxy-quay";
          "registry.k8s.io" = "proxy-k8s";
        };
        description = "Upstream registry to Harbor proxy-cache project. Projects are public, so pulls need no credentials.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."forgejo-registry-pull-token" = {
      sopsFile = "${secrets.profileShared}/forgejo/registry-pull-token.txt";
      format = "binary";
    };

    sops.templates."k3s-registries.yaml" = {
      path = "/etc/rancher/k3s/registries.yaml";
      # Emitted as JSON (a YAML subset): hand-indented YAML with multi-line
      # nix interpolations rendered the mirror keys at column 0 — outside the
      # mirrors map — which is also how the Spegel "*" entry had been silently
      # landing as a dead top-level key.
      #
      # Endpoint semantics: containerd tries mirrors in listed order and
      # always falls back to the upstream registry itself (rewrites do not
      # apply to that default), so an unreachable Harbor costs latency, not
      # availability. With --embedded-registry, k3s additionally prepends the
      # Spegel P2P endpoint: cluster peer -> Harbor cache -> upstream.
      content = builtins.toJSON {
        mirrors = {
          "${cfg.registryHost}".endpoint = [ cfg.endpoint ];
        }
        // lib.optionalAttrs cfg.pullThrough.enable (
          lib.mapAttrs (_upstream: project: {
            endpoint = [ "https://${cfg.pullThrough.harborHost}" ];
            rewrite."^(.*)$" = "${project}/$1";
          }) cfg.pullThrough.mirrors
        )
        // lib.optionalAttrs config.homelab.kubernetes.embeddedRegistry {
          # Serve every other registry through the embedded Spegel P2P
          # cache (peers first, upstream as fallback).
          "*" = { };
        };
        configs."${cfg.registryHost}".auth = {
          inherit (cfg) username;
          password = config.sops.placeholder."forgejo-registry-pull-token";
        };
      };
    };

    # containerd only reads registries.yaml at startup.
    systemd.services.k3s.restartTriggers = [
      config.sops.templates."k3s-registries.yaml".content
    ];
  };
}
