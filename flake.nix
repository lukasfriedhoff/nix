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
  };

  outputs = inputs@{ self, nixpkgs, home-manager, stylix, ... }: 
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      # NixOS hosts
      nixosConfigurations = {
        srv4-vm-01 = nixpkgs.lib.nixosSystem {
          inherit system;
          # Set all inputs parameters as special arguments for all submodules,
          # so you can directly use all dependencies in inputs in submodules
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/srv4-vm-01/configuration.nix

            # enable Stylix on the system side (optional but nice for TTY/SDDM/etc.)
            stylix.nixosModules.stylix
            
            # home manager
            home-manager.nixosModules.home-manager
              {
                home-manager.useGlobalPkgs = true;
                home-manager.useUserPackages = true;

                home-manager.backupFileExtension = "hm-backup";

                home-manager.users.lukasf = {
                  imports = [
                    # theming
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
  };
}
