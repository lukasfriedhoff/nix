{ secrets, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Replace these with the new server's details.
  networking.hostName = "changeme-short";
  networking.domain = "changeme.domain";

  # Personal homelab defaults (DHCP, SSH, bootstrap password) live here.
  homelab.personalServer = {
    enable = true;
    # Default hash corresponds to "ChangeMeNow!" for console logins; override if you prefer another bootstrap secret.
    # defaultPasswordHash = "...";
    # Path to the management SSH *public* key; relative paths resolve via secrets.specialArgs.
    managementPubKey = "ssh/changeme-personal-mgmt.pub";
    # Set to true only if you need temporary SSH password auth.
    usePasswordAuth = false;
  };

  # sops-nix needs the Age key on the build machine.
  sops.age.keyFile = "/home/lukasf/.config/sops/age/keys.txt";

  # Full disk encryption + remote unlock (example; fill in your UUID and pubkey)
  # boot.initrd.luks.devices."cryptroot" = {
  #   device = "/dev/disk/by-uuid/<root-luks-uuid>";
  #   allowDiscards = true;
  # };
  # boot.initrd.network = {
  #   enable = true;
  #   ssh = {
  #     enable = true;
  #     port = 2222;
  #     authorizedKeys = [ "ssh-ed25519 AAAA... ${networking.hostName}-personal-mgmt" ];
  #     generateHostKeys = true;
  #   };
  # };

}
