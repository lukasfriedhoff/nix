{
  inputs,
  secrets,
  ...
}:

{
  imports = [
    inputs.disko.nixosModules.disko
    ./hardware-configuration.nix
    ./disko.nix
  ];

  # Replace these with the new server's details.
  networking.hostName = "changeme-short";
  networking.domain = "changeme.domain";

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

  # sops-nix needs the Age key on the build machine.
  sops.age.keyFile = "/home/lukasf/.config/sops/age/keys.txt";

  # Remote-unlock SSH in initrd; expects ./initrd-authorized.pub to contain the management pubkey.
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;
      authorizedKeys = [ (builtins.readFile ./initrd-authorized.pub) ];
      hostKeys = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
  };

  # Authorize the same key post-boot for root/nixos.
  users.users.root.openssh.authorizedKeys.keys = [ (builtins.readFile ./initrd-authorized.pub) ];
  users.users.nixos.openssh.authorizedKeys.keys = [ (builtins.readFile ./initrd-authorized.pub) ];

  networking.extraHosts = ''
    # changeme-short changeme.domain <ip-optional>
  '';
}
