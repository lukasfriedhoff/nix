{
  defaults = {
    user = "lukasfriedhoff";
    port = 22;
    controlPersist = "10m";
    personalIdentity = "~/.ssh/id_ed25519";
    workIdentity = "~/.ssh/id_ed25519_dacoso";
  };

  hosts = [
    {
      alias = "srv4";
      hostName = "nix-vm-01";
      match = "srv4";
      user = "lukasf";
      description = "Personal Proxmox VM (srv4)";
      identity = "personal";
    }
    {
      alias = "smc-gpu";
      hostName = "smc-gpu-01";
      match = "smc-gpu-01";
      user = "root";
      description = "Homelab GPU worker";
      identity = "personal";
    }
    {
      alias = "dacoso-docker";
      hostName = "docker-host-01";
      match = "docker-host-01";
      user = "root";
      description = "dacoso Docker host";
      identity = "work";
    }
    {
      alias = "dacoso-timebutler";
      hostName = "timebutler-test-vm";
      match = "timebutler-test-vm";
      user = "root";
      description = "dacoso test VM";
      identity = "work";
    }
  ];
}
