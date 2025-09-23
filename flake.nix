{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # home manager
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs"; 

    # theming
    stylix.url = "github:nix-community/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
    
    # mac
    darwin.url = "github:LnL7/nix-darwin";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, home-manager, stylix, darwin, sops-nix, ... }:
    let
      # Linux system for your NixOS hosts
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # Pick your Mac arch: aarch64-darwin (Apple Silicon) or x86_64-darwin (Intel)
      darwinSystem = "aarch64-darwin";
      # darwinSystem = "x86_64-darwin";
    in {
      nixosConfigurations = {
        srv4-vm-01 = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/srv4-vm-01/configuration.nix
            stylix.nixosModules.stylix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "hm-backup";
              home-manager.users.lukasf = {
                imports = [
                  stylix.homeModules.stylix
                  ./home/default.nix
                ];
              };
            }
          ];
        };

        tux-h4xx-01 = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/tux-h4xx-01/configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.lukasf = import ./home/default.nix;
            }
          ];
        };
      };

      ############################
      ## macOS (new)
      ############################
      darwinConfigurations = {
        # The configuration name used by darwin-rebuild (no dots here)
        MacBook-Pro = darwin.lib.darwinSystem {
          system = darwinSystem;
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/MacBook-Pro/darwin-configuration.nix

            # Home Manager on macOS
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;

              # If your Linux HM is portable you can reuse it:
              # home-manager.users.lukasf = import ./home/default.nix;

              # Or keep a mac-specific HM file:
              home-manager.users.lukasf = import ./home/macos.nix;

              # SOPS for HM (decrypts secrets into the home directory)
              imports = [ sops-nix.homeManagerModules.sops ];
            }
          ];
        };
      };
    };
}
