{
  inputs,
  ...
}:

{
  imports = [
    inputs.disko.nixosModules.disko
    ../../common/default.nix
    ../common.nix
    ./hardware-configuration.nix
    ./disko.nix
  ];

  # Replace these with the new server's details.
  networking.hostName = "changeme-short";
  shared.network.domain = "changeme.domain";

  # Personal homelab defaults (DHCP, SSH, bootstrap password) live here.
  homelab.personalServer = {
    enable = true;
    # Default hash corresponds to "ChangeMeNow!" for console logins; override if you prefer another bootstrap secret.
    # defaultPasswordHash = "...";
    # managementPubKey is resolved relative to secrets.specialArgs; leave null when you feed initrd-authorized.pub directly.
    managementPubKey = null;
    # Set to true only if you need temporary SSH password auth.
    usePasswordAuth = false;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.initrdSsh = {
    enable = true;
    authorizedKeyFile = ./initrd-authorized.pub;
  };

  networking.extraHosts = ''
    # changeme-short changeme.domain <ip-optional>
  '';
}
