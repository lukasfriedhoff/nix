{
  description = "Lukas Friedhoff's Nix monorepo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    stylix.url = "github:nix-community/stylix/master";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    comin.url = "github:nlewo/comin";
    comin.inputs.nixpkgs.follows = "nixpkgs";

    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
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
            overlays = [ ];
            config = {
              allowUnfree = false;
              allowUnfreePredicate = pkg: lib.getName pkg == "shadow-client";
            };
          };

          packages = lib.optionalAttrs pkgs.stdenv.isLinux {
            ceph-wrapped = pkgs.callPackage ./pkgs/ceph-wrapped { };
            shadow-client = pkgs.callPackage ./pkgs/shadow-client { };
            tuxedo-control-center = pkgs.callPackage ./pkgs/tuxedo-control-center { };
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
          linuxPkgs = import nixpkgs {
            system = linuxSystem;
            config.allowUnfree = true;
          };
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

          profilesRoot = "${self}/secrets/profiles";
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
            home-manager.extraSpecialArgs = mkSpecialArgs profile // {
              pkgs = linuxPkgs;
            };
            home-manager.users.${linuxUser} = {
              imports = featureModules.home ++ extraImports;
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
              modules = extraModules;
            };
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
          };

          darwinConfigurations.macbook-pro = darwin.lib.darwinSystem {
            system = darwinSystem;
            modules = featureModules.darwin ++ [
              ./hosts/work/macbook-pro/configuration.nix
              home-manager.darwinModules.home-manager
              nix-homebrew.darwinModules.nix-homebrew
              sops-nix.darwinModules.sops
              {
                home-manager = {
                  useGlobalPkgs = false;
                  useUserPackages = true;
                  backupFileExtension = "nixbak";
                  extraSpecialArgs = mkSpecialArgs "mac";
                  users.${macUser} = {
                    nixpkgs.config.allowUnfree = true;
                    imports = featureModules.home ++ [
                      stylix.homeModules.stylix
                    ];
                  };
                };
                nix-homebrew.user = macUser;
              }
            ];
            specialArgs = mkSpecialArgs "mac" // {
              inherit self;
            };
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
