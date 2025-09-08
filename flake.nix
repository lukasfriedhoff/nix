{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.05";

    # home manager
    home-manager.url = "github:nix-community/home-manager/release-25.05";
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

                home-manager.users.lukasf = import ./home/default.nix;

                # enable Stylix for HM
                stylix.homeManagerModules.stylix
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
