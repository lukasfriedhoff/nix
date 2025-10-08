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
    # system-level software and settings (macOS)
    darwin.url = "github:lnl7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs"; 
    # declarative homebrew management
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  };

  outputs = inputs@{ 
    self, 
    nixpkgs, 
    home-manager, 
    stylix, 
    darwin, 
    nix-homebrew, 
    ... 
    }:
    let
      # Linux system for your NixOS hosts
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      linuxUser = "lukasf";

      # mac 
      # arch
      darwinSystem = "aarch64-darwin";
      # macUser
      macUser = "lukasfriedhoff";
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
      darwinConfigurations."macbook-pro" = darwin.lib.darwinSystem {
        system = darwinSystem;
        modules = [
          ./hosts/darwin
          ./hosts/macbook-pro/configuration.nix
        ];
        specialArgs = { inherit inputs self macUser; };
      };
      
    };
}
