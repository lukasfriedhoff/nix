{
  pkgs,
  macUser,
  ...
}:
{
  networking.hostName = "macbook-pro";

  # host-specific homebrew casks
  homebrew.casks = [
    # "slack"
  ];

}
