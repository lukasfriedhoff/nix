{
  description = "Lukas Friedhoff's Nix monorepo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Keep Stylix on the matching release branch so its release checks align with Home Manager.
    stylix.url = "github:nix-community/stylix/release-26.05";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # SOPS-encrypted secrets, kept in a private repo so this one can be
    # public. flake = false because it is a plain source tree, and shallow=1
    # keeps evaluation from cloning its whole history.
    #
    # Anything that evaluates this flake needs read access, and nix evaluates
    # as root, so the key must be readable by root and not only by your user.
    # comin's own auth setting does not cover this: that authenticates comin's
    # fetch of this repo, while flake inputs are fetched separately by nix.
    nix-secrets.url = "git+ssh://git@github.com/lukasfriedhoff/nix-secrets?ref=main&shallow=1";
    nix-secrets.flake = false;

    comin.url = "github:nlewo/comin";
    comin.inputs.nixpkgs.follows = "nixpkgs";

    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";

    witr.url = "github:pranshuparmar/witr";
    witr.inputs.nixpkgs.follows = "nixpkgs";

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
    nix-vscode-extensions.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      home-manager,
      stylix,
      darwin,
      nix-homebrew,
      disko,
      sops-nix,
      comin,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      imports = [
        ./nix/treefmt.nix
        ./nix/tests.nix
      ];

      perSystem =
        {
          system,
          pkgs,
          lib,
          ...
        }:
        {
          _module.args.pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import ./overlays/local-packages.nix) ];
            config = {
              allowUnfree = false;
              allowUnfreePredicate = pkg: lib.getName pkg == "shadow-client-appimage";
            };
          };

          packages = {
            inherit (pkgs) velero_1_9_4;
          }
          // lib.optionalAttrs pkgs.stdenv.isLinux {
            ceph-wrapped = pkgs.callPackage ./pkgs/ceph-wrapped { };
            shadow-client-appimage = pkgs.callPackage ./pkgs/shadow-client-appimage { };
            tuxedo-control-center = pkgs.callPackage ./pkgs/tuxedo-control-center { };
            virtual-05-stream-image = pkgs.callPackage ./pkgs/virtual-05-stream-image { };
          };

          devShells.default = pkgs.mkShell {
            packages =
              (with pkgs; [
                git
                nixfmt
                sops
              ])
              ++ lib.optionals pkgs.stdenv.isLinux (with pkgs; [ sysstat ]);
          };

          devShells.versatelalerting = pkgs.mkShell {
            packages = with pkgs; [
              jdk21
              maven
            ];

            shellHook = ''
              export JAVA_HOME="${pkgs.jdk21}"
              export PATH="$JAVA_HOME/bin:$PATH"
            '';
          };
        };

      flake =
        let
          linuxSystem = "x86_64-linux";
          localPackagesOverlay = import ./overlays/local-packages.nix;
          nixpkgsWorkaroundsOverlay = import ./overlays/nixpkgs-workarounds.nix;
          # Skip flaky openldap tests (test017-syncreplication-refresh).
          # Overriding openldap makes every dependent package uncached, so
          # libvirt gets rebuilt from source — where virt-aa-helper-test
          # fails deterministically in the build sandbox. Skip its checks
          # too, or no desktop closure can ever be built by Hydra.
          openldapOverlay = _final: prev: {
            openldap = prev.openldap.overrideAttrs (_old: {
              doCheck = false;
            });
            libvirt = prev.libvirt.overrideAttrs (_old: {
              doCheck = false;
            });
            # Same story: two of its dbus/pipewire tests are flaky in the
            # build sandbox and dep-fail every desktop closure on Hydra.
            xdg-desktop-portal = prev.xdg-desktop-portal.overrideAttrs (_old: {
              doCheck = false;
            });
          };
          linuxOverlays = [
            localPackagesOverlay
            nixpkgsWorkaroundsOverlay
            openldapOverlay
          ];
          linuxPkgs = import nixpkgs {
            system = linuxSystem;
            config.allowUnfree = true;
            overlays = linuxOverlays;
          };
          mkHomeManagerBackupCommand =
            pkgs: defaultExtension:
            pkgs.writeShellScript "home-manager-backup" ''
              set -eu
              target="$1"
              ext="''${HOME_MANAGER_BACKUP_EXT:-${defaultExtension}}"
              ts="$(date +%Y%m%d-%H%M%S)"
              backup="$target.$ts.$ext"
              i=1
              while [ -e "$backup" ]; do
                backup="$target.$ts-$i.$ext"
                i=$((i + 1))
              done
              mv "$target" "$backup"
            '';
          darwinSystem = "aarch64-darwin";

          myLib = import ./lib { inherit (nixpkgs) lib; };
          featureRoot = ./modules/features;
          featureModules = {
            nixos = myLib.importTreeByName featureRoot "nixos.nix";
            home = myLib.importTreeByName featureRoot "home.nix";
            darwin = myLib.importTreeByName featureRoot "darwin.nix";
          };

          linuxUser = "lukasf";
          macUser = "lukasfriedhoff";

          # Sourced from the private nix-secrets input rather than this repo.
          # The layout there is unchanged, so every path_regex in its
          # .sops.yaml still matches and nothing needed re-encrypting.
          profilesRoot = "${inputs.nix-secrets}/secrets/profiles";
          sharedCommonRoot = "${profilesRoot}/common/shared";
          personalCommonDesktopRoot = "${personalProfileRoot}/desktops/common";
          personalProfileRoot = "${profilesRoot}/personal";
          workProfileRoot = "${profilesRoot}/work";

          personalDesktopRoot = host: "${personalProfileRoot}/desktops/${host}";
          personalServerRoot = host: "${personalProfileRoot}/servers/${host}";
          workDesktopRoot = host: "${workProfileRoot}/desktops/${host}";
          workServerRoot = host: "${workProfileRoot}/servers/${host}";

          personalSharedRoot = "${personalProfileRoot}/shared";
          workSharedRoot = "${workProfileRoot}/shared";

          # Secret roots per host / profile.
          secretsByProfile = {
            srv4 = {
              primary = personalServerRoot "srv4-vm-01";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              ceph = "${personalProfileRoot}/servers/ceph";
              root = personalServerRoot "srv4-vm-01";
              personal = personalServerRoot "srv4-vm-01";
            };
            tux = {
              primary = personalDesktopRoot "tux-h4xx-01";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              ceph = "${personalProfileRoot}/servers/ceph";
              root = personalDesktopRoot "tux-h4xx-01";
              personal = personalDesktopRoot "tux-h4xx-01";
            };
            tab = {
              primary = personalDesktopRoot "tab-h4xx-02";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              ceph = "${personalProfileRoot}/servers/ceph";
              root = personalDesktopRoot "tab-h4xx-02";
              personal = personalDesktopRoot "tab-h4xx-02";
            };
            lenovo = {
              primary = personalDesktopRoot "lenovo-h4xx-03";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              ceph = "${personalProfileRoot}/servers/ceph";
              root = personalDesktopRoot "lenovo-h4xx-03";
              personal = personalDesktopRoot "lenovo-h4xx-03";
            };
            mac = {
              primary = workDesktopRoot "macbook-pro";
              shared = sharedCommonRoot;
              profileShared = workSharedRoot;
              root = workDesktopRoot "macbook-pro";
              dacoso = workDesktopRoot "macbook-pro";
            };
            docker-host-01 = {
              primary = workServerRoot "docker-host-01";
              shared = sharedCommonRoot;
              profileShared = workSharedRoot;
              root = workServerRoot "docker-host-01";
              dacoso = workDesktopRoot "macbook-pro";
            };
            timebutler-test-vm = {
              primary = workServerRoot "timebutler-test-vm";
              shared = sharedCommonRoot;
              profileShared = workSharedRoot;
              root = workServerRoot "timebutler-test-vm";
              dacoso = workDesktopRoot "macbook-pro";
            };

            srv1 = {
              primary = personalServerRoot "srv1";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              ceph = "${personalProfileRoot}/servers/ceph";
              root = personalServerRoot "srv1";
              personal = personalServerRoot "srv1";
            };

            srv2 = {
              primary = personalServerRoot "srv2";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              root = personalServerRoot "srv2";
              personal = personalServerRoot "srv2";
            };

            srv3 = {
              primary = personalServerRoot "srv3";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              ceph = "${personalProfileRoot}/servers/ceph";
              root = personalServerRoot "srv3";
              personal = personalServerRoot "srv3";
            };

            testingrke2-01 = {
              primary = personalServerRoot "testingrke2-01";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              root = personalServerRoot "testingrke2-01";
              personal = personalServerRoot "testingrke2-01";
            };

            testingrke2-02 = {
              primary = personalServerRoot "testingrke2-02";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              root = personalServerRoot "testingrke2-02";
              personal = personalServerRoot "testingrke2-02";
            };

            testingrke2-03 = {
              primary = personalServerRoot "testingrke2-03";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              root = personalServerRoot "testingrke2-03";
              personal = personalServerRoot "testingrke2-03";
            };

            srv5-k3s-stg1 = {
              primary = personalServerRoot "srv5-k3s-stg1";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              root = personalServerRoot "srv5-k3s-stg1";
              personal = personalServerRoot "srv5-k3s-stg1";
            };

            srv6-k3s-stg2 = {
              primary = personalServerRoot "srv6-k3s-stg2";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              root = personalServerRoot "srv6-k3s-stg2";
              personal = personalServerRoot "srv6-k3s-stg2";
            };

            srv7-k3s-stg3 = {
              primary = personalServerRoot "srv7-k3s-stg3";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              root = personalServerRoot "srv7-k3s-stg3";
              personal = personalServerRoot "srv7-k3s-stg3";
            };

            srv8 = {
              primary = personalServerRoot "srv8";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              root = personalServerRoot "srv8";
              personal = personalServerRoot "srv8";
            };

            srv9 = {
              primary = personalServerRoot "srv9";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              root = personalServerRoot "srv9";
              personal = personalServerRoot "srv9";
            };
          };

          workProfiles = [
            "mac"
            "docker-host-01"
            "timebutler-test-vm"
          ];

          mkSpecialArgs = profile: {
            inherit inputs linuxUser macUser;
            inherit profile;
            workSystem = builtins.elem profile workProfiles;
            repoRoot = self;
            secrets = secretsByProfile.${profile};
          };

          mkDesktopHome = profile: extraImports: {
            home-manager.useGlobalPkgs = false;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";
            home-manager.backupCommand = mkHomeManagerBackupCommand linuxPkgs "hm-backup";
            home-manager.extraSpecialArgs = mkSpecialArgs profile // {
              pkgs = linuxPkgs;
            };
            home-manager.users.${linuxUser} = {
              imports = featureModules.home ++ extraImports;
            };
          };

          # Server home configuration (minimal, no GUI)
          # deadnix: skip - exported for future server hosts with home-manager
          mkServerHome = profile: extraImports: {
            home-manager.useGlobalPkgs = false;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-backup";
            home-manager.backupCommand = mkHomeManagerBackupCommand linuxPkgs "hm-backup";
            home-manager.extraSpecialArgs = mkSpecialArgs profile // {
              pkgs = linuxPkgs;
            };
            home-manager.users.${linuxUser} = {
              imports =
                featureModules.home
                ++ extraImports
                ++ [
                  # Explicitly enable server profile
                  { profiles.server.enable = true; }
                ];
            };
          };

          # Shared by ALL NixOS hosts
          coreModules = featureModules.nixos ++ [
            sops-nix.nixosModules.sops
            comin.nixosModules.comin
            inputs.nixos-facter-modules.nixosModules.facter
          ];

          # Additional modules for desktop hosts
          desktopExtras = [
            stylix.nixosModules.stylix
            home-manager.nixosModules.home-manager
          ];

          # Additional modules for server hosts
          serverExtras = [ ];

          # Composed from layers
          baseDesktopModules =
            coreModules
            ++ desktopExtras
            ++ [
              (
                { lib, ... }:
                {
                  lukasf.pipewire.enable = lib.mkDefault true;
                }
              )
            ];

          plasmaDesktopModules = baseDesktopModules ++ [
            (
              { lib, ... }:
              {
                desktop.plasma.enable = lib.mkDefault true;
              }
            )
          ];

          gnomeDesktopModules = baseDesktopModules ++ [
            (
              { lib, ... }:
              {
                desktop.gnome.enable = lib.mkDefault true;
                desktop.laptop.enable = lib.mkDefault true;
              }
            )
          ];

          serverDefaultsModule =
            { lib, ... }:
            {
              lukasf.serverDeployment.enable = lib.mkDefault true;
            };

          dacosoDefaultsModule =
            { lib, ... }:
            {
              dacoso.server.enable = lib.mkDefault true;
            };

          baseServerModules =
            coreModules
            ++ serverExtras
            ++ [
              serverDefaultsModule
              dacosoDefaultsModule
            ];

          homelabServerModules =
            coreModules
            ++ serverExtras
            ++ [
              serverDefaultsModule
            ];

          mkNixosHost =
            profile: extraModules:
            nixpkgs.lib.nixosSystem {
              system = linuxSystem;
              specialArgs = mkSpecialArgs profile // {
                inherit inputs;
              };
              modules = extraModules ++ [
                { nixpkgs.overlays = linuxOverlays; }
              ];
            };

          virtual05Modules = gnomeDesktopModules ++ [
            ./hosts/personal/virtual-05/configuration.nix
            (mkDesktopHome "tux" [
              stylix.homeModules.stylix
            ])
          ];

          virtual05ContainerModules = virtual05Modules ++ [
            "${nixpkgs}/nixos/modules/virtualisation/docker-image.nix"
            (
              { lib, ... }:
              {
                # docker-image profile defaults to host resolv.conf, which conflicts
                # with systemd-resolved from the desktop profile.
                boot.loader.systemd-boot.enable = lib.mkForce false;
                boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
                networking.useHostResolvConf = lib.mkForce false;
                services.resolved.enable = lib.mkForce false;
                documentation.doc.enable = lib.mkForce false;
              }
            )
          ];
        in
        {
          nixosConfigurations = {
            srv4-vm-01 = mkNixosHost "srv4" (
              plasmaDesktopModules
              ++ [
                ./hosts/personal/srv4-vm-01/configuration.nix
                (mkDesktopHome "srv4" [
                  stylix.homeModules.stylix
                ])
              ]
            );

            virtual-05 = mkNixosHost "tux" virtual05Modules;

            virtual-05-container = mkNixosHost "tux" virtual05ContainerModules;

            tux-h4xx-01 = mkNixosHost "tux" (
              gnomeDesktopModules
              ++ [
                ./hosts/personal/tux-h4xx-01/configuration.nix
                (mkDesktopHome "tux" [
                  stylix.homeModules.stylix
                ])
              ]
            );

            tab-h4xx-02 = mkNixosHost "tab" (
              gnomeDesktopModules
              ++ [
                ./hosts/personal/tab-h4xx-02/configuration.nix
                (mkDesktopHome "tab" [
                  stylix.homeModules.stylix
                  ./hosts/personal/tab-h4xx-02/home.nix
                ])
              ]
            );

            lenovo-h4xx-03 = mkNixosHost "lenovo" (
              gnomeDesktopModules
              ++ [
                ./hosts/personal/lenovo-h4xx-03/configuration.nix
                (mkDesktopHome "lenovo" [
                  stylix.homeModules.stylix
                ])
              ]
            );

            lenovo-h4xx-04 = mkNixosHost "lenovo" (
              gnomeDesktopModules
              ++ [
                ./hosts/personal/lenovo-h4xx-04/configuration.nix
                (mkDesktopHome "lenovo" [
                  stylix.homeModules.stylix
                ])
              ]
            );

            docker-host-01 = mkNixosHost "docker-host-01" (
              baseServerModules
              ++ [
                disko.nixosModules.disko
                ./hosts/work/docker-host-01/configuration.nix
              ]
            );

            lf-timebutler-testvm-01 = mkNixosHost "timebutler-test-vm" (
              baseServerModules
              ++ [
                disko.nixosModules.disko
                ./hosts/work/timebutler-test-vm/configuration.nix
              ]
            );

            srv1 = mkNixosHost "srv1" (
              homelabServerModules
              ++ [
                ./hosts/homelab/srv1/configuration.nix
              ]
            );

            srv2 = mkNixosHost "srv2" (
              homelabServerModules
              ++ [
                ./hosts/homelab/srv2/configuration.nix
              ]
            );

            srv3 = mkNixosHost "srv3" (
              homelabServerModules
              ++ [
                ./hosts/homelab/srv3/configuration.nix
              ]
            );

            testingrke2-01 = mkNixosHost "testingrke2-01" (
              homelabServerModules
              ++ [
                ./hosts/homelab/testingrke2-01/configuration.nix
              ]
            );

            testingrke2-02 = mkNixosHost "testingrke2-02" (
              homelabServerModules
              ++ [
                ./hosts/homelab/testingrke2-02/configuration.nix
              ]
            );

            testingrke2-03 = mkNixosHost "testingrke2-03" (
              homelabServerModules
              ++ [
                ./hosts/homelab/testingrke2-03/configuration.nix
              ]
            );

            srv5-k3s-stg1 = mkNixosHost "srv5-k3s-stg1" (
              homelabServerModules
              ++ [
                ./hosts/homelab/srv5-k3s-stg1/configuration.nix
              ]
            );

            srv6-k3s-stg2 = mkNixosHost "srv6-k3s-stg2" (
              homelabServerModules
              ++ [
                ./hosts/homelab/srv6-k3s-stg2/configuration.nix
              ]
            );

            srv7-k3s-stg3 = mkNixosHost "srv7-k3s-stg3" (
              homelabServerModules
              ++ [
                ./hosts/homelab/srv7-k3s-stg3/configuration.nix
              ]
            );

            srv8 = mkNixosHost "srv8" (
              homelabServerModules
              ++ [
                ./hosts/homelab/srv8/configuration.nix
              ]
            );

            srv9 = mkNixosHost "srv9" (
              homelabServerModules
              ++ [
                ./hosts/homelab/srv9/configuration.nix
              ]
            );
          };

          hydraJobs.nixosConfigurations = builtins.mapAttrs (
            _name: nixosConfiguration: nixosConfiguration.config.system.build.toplevel
          ) self.nixosConfigurations;

          darwinConfigurations.macbook-pro = darwin.lib.darwinSystem {
            system = darwinSystem;
            modules = featureModules.darwin ++ [
              ./hosts/work/macbook-pro/configuration.nix
              home-manager.darwinModules.home-manager
              nix-homebrew.darwinModules.nix-homebrew
              sops-nix.darwinModules.sops
              (
                { pkgs, ... }:
                {
                  home-manager = {
                    useGlobalPkgs = false;
                    useUserPackages = true;
                    backupFileExtension = "nixbak";
                    backupCommand = mkHomeManagerBackupCommand pkgs "nixbak";
                    extraSpecialArgs = mkSpecialArgs "mac" // {
                      inherit inputs;
                    };
                    users.${macUser} = {
                      nixpkgs.config.allowUnfree = true;
                      nixpkgs.overlays = [
                        localPackagesOverlay
                        inputs.nix-vscode-extensions.overlays.default
                      ];
                      imports = featureModules.home ++ [
                        stylix.homeModules.stylix
                      ];
                    };
                  };
                  nix-homebrew.user = macUser;
                }
              )
            ];
            specialArgs = mkSpecialArgs "mac" // {
              inherit self;
            };
          };

          # Reusable Home Manager modules for different profiles
          homeModules = {
            # Core shared configuration
            core = ./modules/features/profile/core/home.nix;
            # Server profile (minimal, CLI only)
            server = ./modules/features/profile/server/home.nix;
            # Desktop profile (full GUI and development tools)
            desktop = ./modules/features/profile/desktop/home.nix;
          };

          homeConfigurations =
            let
              mkStandaloneHome =
                {
                  username,
                  system,
                  profile,
                  extraImports ? [ ],
                }:
                let
                  hmPkgs = import nixpkgs {
                    inherit system;
                    overlays = [ localPackagesOverlay ];
                    config.allowUnfree = true;
                  };
                in
                home-manager.lib.homeManagerConfiguration {
                  pkgs = hmPkgs;
                  extraSpecialArgs = mkSpecialArgs profile // {
                    pkgs = hmPkgs;
                  };
                  modules = featureModules.home ++ extraImports;
                  inherit username;
                  homeDirectory = if system == darwinSystem then "/Users/${username}" else "/home/${username}";
                };
            in
            {
              "${linuxUser}@desktop" = mkStandaloneHome {
                username = linuxUser;
                system = linuxSystem;
                profile = "tux";
                extraImports = [
                  stylix.homeModules.stylix
                ];
              };
              "${macUser}@macbook-pro" = mkStandaloneHome {
                username = macUser;
                system = darwinSystem;
                profile = "mac";
              };
            };
        };
    };
}
