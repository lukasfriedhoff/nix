[
  {
    match = "storage01";
    alias = "storage01";
    user = "lukasf";
    identityFile = "~/.ssh/personal/storage01";
  }
  {
    match = "docker-host";
    alias = "docker-host";
    user = "root";
    identityFile = "~/.ssh/personal/docker-host";
  }
  {
    match = "srv4";
    alias = "srv4";
    user = "lukasf";
    identityFile = "~/.ssh/personal/srv4";
  }
  {
    match = "srv4-root";
    alias = "srv4-root";
    user = "root";
    identityFile = "~/.ssh/personal/srv4";
  }
  {
    match = "cisrv4";
    alias = "cisrv4";
    user = "ci";
    identityFile = "~/.ssh/personal/ci";
  }
  {
    match = "rem-srv4";
    alias = "rem-srv4";
    port = 61348;
    user = "lukasf";
    identityFile = "~/.ssh/personal/srv4";
  }
  {
    match = "ionos1";
    alias = "ionos1";
    user = "h4xx";
    identityFile = "~/.ssh/personal/ionos1";
  }
  {
    match = "ionos2";
    alias = "ionos2";
    user = "h4xx";
    identityFile = "~/.ssh/personal/ionos2";
  }
  {
    match = "router01.h4xx.local";
    alias = "router01.h4xx.local";
    user = "root";
    identityFile = "~/.ssh/personal/router01.h4xx.local";
  }
  {
    match = "nas01";
    alias = "nas01";
    user = "h4xx";
    identityFile = "~/.ssh/personal/nas01";
  }
  {
    match = "unlock-nas01";
    alias = "unlock-nas01";
    port = 2222;
    user = "root";
    identityFile = "~/.ssh/personal/nas01-unlock";
  }
  {
    match = "srv1";
    alias = "srv1";
    hostName = "srv1.lab.h4xx.io";
    user = "root";
    keyName = "srv1-personal-mgmt";
  }
  {
    match = "unlock-srv1";
    alias = "unlock-srv1";
    hostName = "srv1.lab.h4xx.io";
    port = 2222;
    user = "root";
    keyName = "srv1-personal-mgmt";
  }
  {
    match = "srv2";
    alias = "srv2";
    hostName = "srv2.lab.h4xx.io";
    user = "root";
    keyName = "srv2-personal-mgmt";
  }
  {
    match = "unlock-srv2";
    alias = "unlock-srv2";
    hostName = "srv2.lab.h4xx.io";
    port = 2222;
    user = "root";
    keyName = "srv2-personal-mgmt";
  }

]
