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

  networking.hostName = "srv1";
  networking.domain = "h4xx.local";

  homelab.personalServer = {
    enable = true;
    managementPubKey = null;
    usePasswordAuth = false;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  sops.age.keyFile = "/home/lukasf/.config/sops/age/keys.txt";

  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;
      authorizedKeys = [ (builtins.readFile ./initrd-authorized.pub) ];
      hostKeys = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [ (builtins.readFile ./initrd-authorized.pub) ];
  users.users.nixos.openssh.authorizedKeys.keys = [ (builtins.readFile ./initrd-authorized.pub) ];

  networking.extraHosts = ''
    # srv1 srv1.h4xx.local 10.1.30.12
  '';
}
