{
  config,
  lib,
  pkgs,
  secrets ? { },
  ...
}:
# Shared profile for Dacoso-managed servers. Secrets are resolved via the
# `secrets` specialArg so work and personal machines can remain isolated.
let
  cfg = config.dacoso.server;
  primaryRoot = secrets.primary or secrets.root or null;
  sharedRoot = secrets.shared or null;

  resolve =
    file:
    if file == null then
      null
    else
      let
        pathString = toString file;
        resolveRelative =
          if cfg.secretsDirectory != null then
            "${cfg.secretsDirectory}/${pathString}"
          else
            let
              candidates =
                (lib.optional (primaryRoot != null) "${primaryRoot}/${pathString}")
                ++ (lib.optional (sharedRoot != null) "${sharedRoot}/${pathString}");
              existing = lib.findFirst (p: builtins.pathExists p) null candidates;
            in
            if existing != null then
              existing
            else if candidates != [ ] then
              lib.head candidates
            else
              pathString;
      in
      if lib.hasPrefix "/" pathString then pathString else resolveRelative;

  readHash =
    file:
    let
      resolved = resolve file;
    in
    if resolved == null then null else lib.strings.trim (builtins.readFile resolved);

  readKeys =
    files:
    lib.flatten (
      map (
        file:
        let
          resolved = resolve file;
        in
        if resolved == null then
          [ ]
        else
          lib.filter (line: line != "") (
            map lib.strings.trim (lib.splitString "\n" (builtins.readFile resolved))
          )
      ) files
    );

  rootPasswordHash =
    let
      fromFile = readHash cfg.passwordFiles.root;
    in
    if fromFile != null then fromFile else cfg.hashedPasswords.root;

  nixosPasswordHash =
    let
      fromFile = readHash cfg.passwordFiles.nixos;
    in
    if fromFile != null then fromFile else cfg.hashedPasswords.nixos;

  nixosAuthorizedKeys = cfg.sshKeys.nixos ++ readKeys cfg.sshKeyFiles.nixos;
  rootAuthorizedKeys = lib.unique (
    cfg.sshKeys.root ++ readKeys cfg.sshKeyFiles.root ++ nixosAuthorizedKeys
  );

  githubKeyDir = "/var/lib/dacoso-github-keys";
  githubKeyFile = "${githubKeyDir}/github.keys";
  githubAccountsArg = lib.concatMapStringsSep " " (user: lib.escapeShellArg user) cfg.githubAccounts;
  syncGithubKeysScript = pkgs.writeShellScript "dacoso-sync-github-keys" ''
    set -euo pipefail

    dest=${lib.escapeShellArg githubKeyFile}
    tmp=$(${pkgs.coreutils}/bin/mktemp)
    trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
    > "$tmp"

    for account in ${githubAccountsArg}; do
      echo "# github:$account" >> "$tmp"
      if ${pkgs.curl}/bin/curl -fsSL "https://github.com/$account.keys" >> "$tmp"; then
        echo "" >> "$tmp"
      else
        echo "# warning: failed to fetch $account" >&2
      fi
    done

    if [ -s "$tmp" ]; then
      ${pkgs.coreutils}/bin/install -D -m 600 "$tmp" "$dest"
    else
      ${pkgs.coreutils}/bin/rm -f "$dest"
    fi
  '';

  repoKeysFile =
    let
      repo = cfg.authorizedKeysRepo;
      sanitize =
        content: lib.filter (line: line != "") (map lib.strings.trim (lib.splitString "\n" content));
    in
    if repo == null then
      null
    else
      let
        repoPath = pkgs.fetchgit {
          inherit (repo) url rev sha256;
          fetchSubmodules = repo.fetchSubmodules or false;
        };
        repoStr = toString repoPath;
        files = repo.files or [ "authorized_keys" ];
        contents = lib.concatStringsSep "\n" (
          lib.flatten (
            map (
              file:
              let
                path = "${repoStr}/${file}";
              in
              if builtins.pathExists path then
                sanitize (builtins.readFile path)
              else
                lib.warn "dacoso.server: repo file ${file} not found" [ ]
            ) files
          )
        );
      in
      if contents == "" then null else pkgs.writeText "dacoso-shared-keys" (contents + "\n");

  repoKeyFiles = lib.optionals (repoKeysFile != null) [ repoKeysFile ];
in
{
  options.dacoso.server = {
    enable = lib.mkEnableOption "Dacoso server profile";

    secretsDirectory = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = primaryRoot;
      description = ''Base directory containing work secrets; relative file references resolve against this path.'';
    };

    hashedPasswords = {
      root = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SHA-512 hashed password for the root user.";
      };
      nixos = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SHA-512 hashed password for the service user nixos.";
      };
    };

    passwordFiles = {
      root = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional path (absolute or relative to secretsDirectory) containing the root password hash.";
      };
      nixos = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional path (absolute or relative to secretsDirectory) containing the nixos user password hash.";
      };
    };

    sshKeys = {
      root = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Authorized SSH keys for the root user.";
      };
      nixos = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Authorized SSH keys for the nixos user.";
      };
    };

    sshKeyFiles = {
      root = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Files (absolute or relative) appended to root's authorized_keys.";
      };
      nixos = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Files (absolute or relative) appended to nixos' authorized_keys.";
      };
    };

    authorizedKeysRepo = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            url = lib.mkOption {
              type = lib.types.str;
              description = "Git repository URL containing shared public keys.";
            };
            rev = lib.mkOption {
              type = lib.types.str;
              description = "Pinned Git revision for reproducible deployments.";
            };
            sha256 = lib.mkOption {
              type = lib.types.str;
              description = "Expected SHA256 of the fetched repository.";
            };
            fetchSubmodules = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether to fetch submodules when pulling the repository.";
            };
            files = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "authorized_keys" ];
              description = "Relative file paths inside the repository that contain OpenSSH public keys.";
            };
          };
        }
      );
      default = null;
      description = "Repository providing shared authorized_keys material for work hosts.";
    };

    githubAccounts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "GitHub usernames whose published keys should be installed for both root and the server user.";
    };

    githubRefreshInterval = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "daily";
      description = "Optional systemd.timer OnCalendar expression to refresh GitHub keys periodically.";
    };

    extraSystemPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional packages for the server profile.";
    };

    enableNodeExporter = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable the Prometheus node exporter.";
    };

    firewallEnabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Firewall state override.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.optionals (cfg.secretsDirectory == null) [
      {
        assertion =
          (cfg.passwordFiles.root or null) == null
          && (cfg.passwordFiles.nixos or null) == null
          && cfg.sshKeyFiles.root == [ ]
          && cfg.sshKeyFiles.nixos == [ ];
        message = "Relative password/SSH key files require dacoso.server.secretsDirectory to be set.";
      }
    ];

    networking.firewall.enable = cfg.firewallEnabled;

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "yes";
        PasswordAuthentication = true;
      };
    };

    services.openssh.authorizedKeysFiles = lib.mkIf (cfg.githubAccounts != [ ]) (
      lib.mkAfter [ "${githubKeyDir}/github.keys" ]
    );

    systemd.tmpfiles.rules = lib.optionals (cfg.githubAccounts != [ ]) [
      "d ${githubKeyDir} 0700 root root -"
    ];

    systemd.services.dacoso-github-keys = lib.mkIf (cfg.githubAccounts != [ ]) {
      description = "Synchronise GitHub SSH keys for Dacoso server accounts";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = [ syncGithubKeysScript ];
      };
    };

    systemd.timers.dacoso-github-keys =
      lib.mkIf (cfg.githubAccounts != [ ] && cfg.githubRefreshInterval != null)
        {
          description = "Periodic refresh of GitHub SSH keys";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.githubRefreshInterval;
            Persistent = true;
          };
        };

    system.activationScripts.dacosoGithubKeys = lib.mkIf (cfg.githubAccounts != [ ]) ''
      echo "syncing GitHub keys for dacoso server users"
      ${syncGithubKeysScript}
    '';

    services.prometheus.exporters.node.enable = cfg.enableNodeExporter;

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    users.mutableUsers = false;
    programs.direnv.enable = true;

    security.sudo.wheelNeedsPassword = false;

    users.users = {
      root = {
        openssh.authorizedKeys = {
          keys = rootAuthorizedKeys;
          keyFiles = repoKeyFiles;
        };
        hashedPassword = lib.mkIf (rootPasswordHash != null) rootPasswordHash;
      };

      nixos = {
        isNormalUser = true;
        shell = pkgs.bash;
        description = "nixos user";
        extraGroups = [
          "networkmanager"
          "wheel"
          "docker"
        ];
        openssh.authorizedKeys = {
          keys = nixosAuthorizedKeys;
          keyFiles = repoKeyFiles;
        };
        hashedPassword = lib.mkIf (nixosPasswordHash != null) nixosPasswordHash;
      };
    };

    environment.systemPackages =
      let
        basePackages = with pkgs; [
          curl
          gitMinimal
          bash
          vim
          tmux
          wget
          htop
          jq
          direnv
          python3
          python3Packages.pip
        ];
      in
      map lib.lowPrio (basePackages ++ cfg.extraSystemPackages);

  };
}
