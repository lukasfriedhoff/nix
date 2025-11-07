{
  pkgs,
  inputs,
  self,
  macUser,
  ...
}:
{
  imports = [
    #./homebrew.nix
    ./settings.nix
    inputs.home-manager.darwinModules.home-manager
    inputs.nix-homebrew.darwinModules.nix-homebrew
  ];

  # nix config
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # disabled due to https://github.com/NixOS/nix/issues/7273
      # auto-optimise-store = true;
    };
    enable = false; # using determinate installer
  };

  nixpkgs.config.allowUnfree = true;

  # homebrew installation manager
  nix-homebrew = {
    user = macUser;
    enable = true;
    autoMigrate = true;
  };

  # home-manager config
  home-manager = {
    useGlobalPkgs = false;
    useUserPackages = true;
    users.${macUser} = {
      imports = [
        ../../home/default.nix
      ];
    };
    backupFileExtension = "nixbak";
    extraSpecialArgs = {
      inherit inputs self macUser;
    };
  };

  # macOS-specific settings
  system.primaryUser = macUser;
  users.users.${macUser} = {
    home = "/Users/${macUser}";
    shell = pkgs.bashInteractive;
  };
  environment = {
    systemPath = [
      "/opt/homebrew/bin"
    ];
    pathsToLink = [ "/Applications" ];
  };
}
