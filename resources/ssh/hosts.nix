{
  defaults = {
    user = "lukasfriedhoff";
    port = 22;
    controlPersist = "10m";
    personalIdentity = "~/.ssh/personal/id_ed25519";
    workIdentity = "~/.ssh/id_ed25519_dacoso";
  };

  # Tip: set keyName to use ~/.ssh/personal/<name> for personal homelab nodes.
  hosts = [
    {
      match = "storage01";
      alias = "storage01";
      hostName = "10.1.30.15";
      user = "lukasf";
      identityFile = "~/.ssh/personal/storage01";
    }
    {
      match = "docker-host";
      alias = "docker-host";
      hostName = "10.0.11.22";
      user = "root";
      identityFile = "~/.ssh/personal/docker-host";
    }
    {
      match = "srv4";
      alias = "srv4";
      hostName = "10.0.10.104";
      user = "lukasf";
      identityFile = "~/.ssh/personal/srv4";
    }
    {
      match = "srv4-root";
      alias = "srv4-root";
      hostName = "10.0.10.104";
      user = "root";
      identityFile = "~/.ssh/personal/srv4";
    }
    {
      match = "cisrv4";
      alias = "cisrv4";
      hostName = "10.0.10.104";
      user = "ci";
      identityFile = "~/.ssh/personal/ci";
    }
    {
      match = "rem-srv4";
      alias = "rem-srv4";
      hostName = "217.160.11.254";
      port = 61348;
      user = "lukasf";
      identityFile = "~/.ssh/personal/srv4";
    }
    {
      match = "ionos1";
      alias = "ionos1";
      hostName = "217.160.11.254";
      user = "h4xx";
      identityFile = "~/.ssh/personal/ionos1";
    }
    {
      match = "ionos2";
      alias = "ionos2";
      hostName = "82.165.126.40";
      user = "h4xx";
      identityFile = "~/.ssh/personal/ionos2";
    }
    {
      match = "router01.h4xx.local";
      alias = "router01.h4xx.local";
      hostName = "10.0.0.1";
      user = "root";
      identityFile = "~/.ssh/personal/router01.h4xx.local";
    }
    {
      match = "nas01";
      alias = "nas01";
      hostName = "10.0.10.50";
      user = "h4xx";
      identityFile = "~/.ssh/personal/nas01";
    }
    {
      match = "unlock-nas01";
      alias = "unlock-nas01";
      hostName = "10.0.10.50";
      port = 2222;
      user = "root";
      identityFile = "~/.ssh/personal/nas01-unlock";
    }
    {
      match = "srv1";
      alias = "srv1";
      hostName = "10.1.30.12";
      user = "root";
      keyName = "srv1-personal-mgmt";
    }
    {
      match = "unlock-srv1";
      alias = "unlock-srv1";
      hostName = "10.1.30.12";
      port = 2222;
      user = "root";
      keyName = "srv1-personal-mgmt";
    }
  ];
}
