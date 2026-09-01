{
  pkgs,
  macUser,
  ...
}:
{
  imports = [
    ./settings.nix
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
    # Managed by nix-darwin: the upstream installer's nix.conf is replaced on
    # the first switch (the old one is kept as nix.conf.before-nix-darwin).
    enable = true;
  };

  nixpkgs.config.allowUnfree = true;

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
