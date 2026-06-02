{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.kubeconfig;

  escape = lib.escapeShellArg;

  mkClusterSnippet =
    cluster:
    let
      outputName =
        if cluster.outputName == null || cluster.outputName == "" then
          "${cluster.name}.yaml"
        else
          cluster.outputName;
      apiServer = cluster.apiServer or "";
      contextName = cluster.contextName or "";
      userName = "${cluster.name}-user";
      strictFlag = if cluster.strict then "1" else "0";
    in
    ''
      # cluster: ${cluster.name}
      cluster_name=${escape cluster.name}
      cluster_mode=${escape cluster.mode}
      cluster_api_server=${escape apiServer}
      cluster_context_name=${escape contextName}
      cluster_user_name=${escape userName}
      cluster_strict=${strictFlag}
      output_file="$cluster_dir/${outputName}"
      tmp_file="$(mktemp "$tmp_root/${outputName}.XXXXXX")"
      fetch_ok=1

      case "$cluster_mode" in
        ssh)
          ssh_opts=(
            -o BatchMode=yes
            -o ConnectTimeout=8
            -o StrictHostKeyChecking=accept-new
            -o UserKnownHostsFile="$known_hosts_file"
            -o GlobalKnownHostsFile=/dev/null
            -o CheckHostIP=no
          )
          if ! ssh "''${ssh_opts[@]}" ${escape cluster.sshHost} ${escape cluster.sshCommand} > "$tmp_file"; then
            # Hosts are reprovisioned frequently in homelab; retry once after dropping stale host key.
            ssh-keygen -R ${escape cluster.sshHost} -f "$known_hosts_file" >/dev/null 2>&1 || true
            if ! ssh "''${ssh_opts[@]}" ${escape cluster.sshHost} ${escape cluster.sshCommand} > "$tmp_file"; then
              fetch_ok=0
            fi
          fi
          ;;
        file)
          if ! cp ${escape cluster.sourceFile} "$tmp_file"; then
            fetch_ok=0
          fi
          ;;
      esac

      if [ "$fetch_ok" -ne 1 ]; then
        echo "[kubeconfig] WARN: failed to refresh $cluster_name ($cluster_mode)" >&2
        if [ "$cluster_strict" -eq 1 ]; then
          had_error=1
        fi
        rm -f "$tmp_file"
      else
        # Normalize cluster and user object names to avoid merged kubeconfig
        # collisions when remote kubeconfigs all ship "default".
        source_cluster="$(kubectl --kubeconfig "$tmp_file" config view -o jsonpath='{.clusters[0].name}' 2>/dev/null || true)"
        source_server="$(kubectl --kubeconfig "$tmp_file" config view -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"
        source_ca_data="$(kubectl --kubeconfig "$tmp_file" config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' 2>/dev/null || true)"
        if [ -n "$source_server" ]; then
          kubectl --kubeconfig "$tmp_file" config set-cluster "$cluster_name" --server="$source_server" >/dev/null 2>&1 || true
        fi
        if [ -n "$source_ca_data" ]; then
          kubectl --kubeconfig "$tmp_file" config set "clusters.$cluster_name.certificate-authority-data" "$source_ca_data" >/dev/null 2>&1 || true
        fi
        if [ -n "$source_cluster" ] && [ "$source_cluster" != "$cluster_name" ]; then
          kubectl --kubeconfig "$tmp_file" config delete-cluster "$source_cluster" >/dev/null 2>&1 || true
        fi

        source_user="$(kubectl --kubeconfig "$tmp_file" config view -o jsonpath='{.users[0].name}' 2>/dev/null || true)"
        source_client_cert="$(kubectl --kubeconfig "$tmp_file" config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' 2>/dev/null || true)"
        source_client_key="$(kubectl --kubeconfig "$tmp_file" config view --raw -o jsonpath='{.users[0].user.client-key-data}' 2>/dev/null || true)"
        kubectl --kubeconfig "$tmp_file" config set-credentials "$cluster_user_name" >/dev/null 2>&1 || true
        if [ -n "$source_client_cert" ]; then
          kubectl --kubeconfig "$tmp_file" config set "users.$cluster_user_name.client-certificate-data" "$source_client_cert" >/dev/null 2>&1 || true
        fi
        if [ -n "$source_client_key" ]; then
          kubectl --kubeconfig "$tmp_file" config set "users.$cluster_user_name.client-key-data" "$source_client_key" >/dev/null 2>&1 || true
        fi
        if [ -n "$source_user" ] && [ "$source_user" != "$cluster_user_name" ]; then
          kubectl --kubeconfig "$tmp_file" config unset "users.$source_user" >/dev/null 2>&1 || true
        fi

        if [ -n "$cluster_api_server" ]; then
          kubectl --kubeconfig "$tmp_file" config set-cluster "$cluster_name" --server "$cluster_api_server" >/dev/null 2>&1 || true
        fi

        if [ -n "$cluster_context_name" ]; then
          current_ctx="$(kubectl --kubeconfig "$tmp_file" config current-context 2>/dev/null || true)"
          if [ -n "$current_ctx" ] && [ "$current_ctx" != "$cluster_context_name" ]; then
            kubectl --kubeconfig "$tmp_file" config rename-context "$current_ctx" "$cluster_context_name" >/dev/null 2>&1 || true
          fi
          kubectl --kubeconfig "$tmp_file" config set-context "$cluster_context_name" --cluster "$cluster_name" --user "$cluster_user_name" >/dev/null 2>&1 || true
          kubectl --kubeconfig "$tmp_file" config use-context "$cluster_context_name" >/dev/null 2>&1 || true
        else
          current_ctx="$(kubectl --kubeconfig "$tmp_file" config current-context 2>/dev/null || true)"
          if [ -n "$current_ctx" ]; then
            kubectl --kubeconfig "$tmp_file" config set-context "$current_ctx" --cluster "$cluster_name" --user "$cluster_user_name" >/dev/null 2>&1 || true
          fi
        fi

        install -m 0600 "$tmp_file" "$output_file"
        rm -f "$tmp_file"
      fi
    '';

  clusterSnippets = lib.concatStringsSep "\n" (map mkClusterSnippet cfg.clusters);

  refreshScript = pkgs.writeShellApplication {
    name = "kubeconfig-refresh";
    runtimeInputs = [
      cfg.package
      pkgs.openssh
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      set -euo pipefail

      kube_dir=${escape cfg.kubeDir}
      cluster_dir="$kube_dir/clusters"
      known_hosts_file="$kube_dir/known_hosts"
      config_file=${escape cfg.configPath}
      default_context=${escape (cfg.defaultContext or "")}

      mkdir -p "$cluster_dir"
      touch "$known_hosts_file"

      tmp_root="$(mktemp -d)"
      had_error=0
      trap 'rm -rf "$tmp_root"' EXIT

      ${clusterSnippets}

      mapfile -t kube_files < <(find "$cluster_dir" -maxdepth 1 -type f -name '*.yaml' | sort)
      if [ "''${#kube_files[@]}" -eq 0 ]; then
        echo "[kubeconfig] WARN: no kubeconfig files available under $cluster_dir; keeping existing $config_file" >&2
        exit "$had_error"
      fi

      merged_kubeconfig="$(IFS=:; echo "''${kube_files[*]}")"
      if ! KUBECONFIG="$merged_kubeconfig" kubectl config view --flatten > "$tmp_root/config"; then
        echo "[kubeconfig] ERROR: failed to merge kubeconfigs" >&2
        exit 1
      fi

      if [ -n "$default_context" ]; then
        kubectl --kubeconfig "$tmp_root/config" config use-context "$default_context" >/dev/null 2>&1 || true
      fi

      mkdir -p "$(dirname "$config_file")"
      install -m 0600 "$tmp_root/config" "$config_file"

      exit "$had_error"
    '';
  };
in
{
  options.programs.kubeconfig = {
    enable = lib.mkEnableOption "declarative kubeconfig refresh/merge via Home Manager";

    package = lib.mkPackageOption pkgs "kubectl" { };

    kubeDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.kube";
      description = "Directory containing generated kubeconfig fragments.";
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.kube/config";
      description = "Merged kubeconfig output path.";
    };

    defaultContext = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional default context to set in the merged kubeconfig.";
    };

    refreshOnActivation = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Refresh and merge kubeconfigs during Home Manager activation.";
    };

    clusters = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                default = name;
                description = "Logical cluster name used for diagnostics.";
              };

              mode = lib.mkOption {
                type = lib.types.enum [
                  "ssh"
                  "file"
                ];
                default = "ssh";
                description = "How to load the source kubeconfig.";
              };

              outputName = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Filename under ~/.kube/clusters; defaults to <name>.yaml.";
              };

              sshHost = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "SSH host/alias used in ssh mode.";
              };

              sshCommand = lib.mkOption {
                type = lib.types.str;
                default = "cat /etc/rancher/k3s/k3s.yaml";
                description = "Remote command used in ssh mode to print kubeconfig.";
              };

              sourceFile = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "Local source file used in file mode.";
              };

              apiServer = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Optional API server URL override applied to all clusters in this kubeconfig.";
              };

              contextName = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Optional context name override for the kubeconfig current context.";
              };

              strict = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Fail refresh when this cluster cannot be fetched.";
              };
            };
          }
        )
      );
      default = [ ];
      description = "Cluster kubeconfig sources to refresh and merge.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = map (cluster: {
      assertion = if cluster.mode == "ssh" then cluster.sshHost != "" else cluster.sourceFile != "";
      message =
        if cluster.mode == "ssh" then
          "programs.kubeconfig cluster '${cluster.name}' requires sshHost for mode=ssh."
        else
          "programs.kubeconfig cluster '${cluster.name}' requires sourceFile for mode=file.";
    }) cfg.clusters;

    home.packages = [ cfg.package ];

    home.file.".local/bin/kubeconfig-refresh" = {
      source = "${refreshScript}/bin/kubeconfig-refresh";
      executable = true;
      force = true;
    };

    home.sessionVariables.KUBECONFIG = cfg.configPath;

    programs.bash.shellAliases = {
      kcfg-refresh = "~/.local/bin/kubeconfig-refresh";
      kcfg-show = "kubectl config get-contexts";
    };

    home.activation.refreshKubeconfig = lib.mkIf cfg.refreshOnActivation (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ -x "${config.home.homeDirectory}/.local/bin/kubeconfig-refresh" ]; then
          "${config.home.homeDirectory}/.local/bin/kubeconfig-refresh" || true
        fi
      ''
    );
  };
}
