{
  defaults = {
    user = "lukasfriedhoff";
    port = 22;
    controlPersist = "10m";
    personalIdentity = "~/.ssh/personal/id_ed25519";
    workIdentity = "~/.ssh/id_ed25519_dacoso";
  };

  hosts = [
    {
      match = "sunbeam01";
      alias = "sunbeam01";
      hostName = "sunbeam01.lab.h4xx.io";
      user = "lukasf";
      identityFile = "~/.ssh/openstack-sunbeam";
    }
    {
      match = "sunbeam02";
      alias = "sunbeam02";
      hostName = "sunbeam02.lab.h4xx.io";
      user = "lukasf";
      identityFile = "~/.ssh/openstack-sunbeam";
    }
    {
      match = "sunbeam03";
      alias = "sunbeam03";
      hostName = "sunbeam03.lab.h4xx.io";
      user = "lukasf";
      identityFile = "~/.ssh/openstack-sunbeam";
    }
    {
      match = "storage01";
      alias = "storage01";
      hostName = "10.1.30.15";
      user = "lukasf";
      identityFile = "~/.ssh/personal/storage01";
    }
    {
      match = "cp01";
      alias = "cp01";
      hostName = "cp01.h4xx.local";
      user = "ci";
      identityFile = "~/.ssh/personal/ci";
    }
    {
      match = "cp02";
      alias = "cp02";
      hostName = "cp02.h4xx.local";
      user = "ci";
      identityFile = "~/.ssh/personal/ci";
    }
    {
      match = "cp03";
      alias = "cp03";
      hostName = "cp03.h4xx.local";
      user = "ci";
      identityFile = "~/.ssh/personal/ci";
    }
    {
      match = "worker01";
      alias = "worker01";
      hostName = "worker01.h4xx.local";
      user = "ci";
      identityFile = "~/.ssh/personal/ci";
    }
    {
      match = "worker02";
      alias = "worker02";
      hostName = "worker02.h4xx.local";
      user = "ci";
      identityFile = "~/.ssh/personal/ci";
    }
    {
      match = "worker03";
      alias = "worker03";
      hostName = "worker03.h4xx.local";
      user = "ci";
      identityFile = "~/.ssh/personal/ci";
    }
    {
      match = "worker04";
      alias = "worker04";
      hostName = "worker04.h4xx.local";
      user = "ci";
      identityFile = "~/.ssh/personal/ci";
    }
    {
      match = "gitlab.h4.ddnss.org";
      alias = "gitlab.h4.ddnss.org";
      hostName = "gitlab.h4.ddnss.org";
      user = "git";
      identityFile = "~/.ssh/gitlab";
    }
    {
      match = "ceph01";
      alias = "ceph01";
      hostName = "ceph01";
      user = "root";
      identityFile = "~/.ssh/ceph";
    }
    {
      match = "ceph02";
      alias = "ceph02";
      hostName = "ceph02";
      user = "root";
      identityFile = "~/.ssh/ceph";
    }
    {
      match = "ceph03";
      alias = "ceph03";
      hostName = "ceph03";
      user = "root";
      identityFile = "~/.ssh/ceph";
    }
    {
      match = "docker-host";
      alias = "docker-host";
      hostName = "10.0.11.22";
      user = "root";
      identityFile = "~/.ssh/personal/docker-host";
    }
    {
      match = "srv1";
      alias = "srv1";
      hostName = "10.0.10.101";
      user = "h4xx";
      identityFile = "~/.ssh/personal/srv1";
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
      match = "unlock-srv3";
      alias = "unlock-srv3";
      hostName = "10.0.10.103";
      port = 2222;
      user = "root";
      identityFile = "~/.ssh/srv3-unlock";
    }
    {
      match = "rem-unlock-srv3";
      alias = "rem-unlock-srv3";
      hostName = "217.160.11.254";
      port = 61344;
      user = "root";
      identityFile = "~/.ssh/srv3-unlock";
    }
    {
      match = "rem-srv3";
      alias = "rem-srv3";
      hostName = "217.160.11.254";
      port = 61345;
      user = "h4xx";
      identityFile = "~/.ssh/srv3";
    }
    {
      match = "unlock-srv2";
      alias = "unlock-srv2";
      hostName = "10.0.10.102";
      port = 2222;
      user = "root";
      identityFile = "~/.ssh/srv2";
    }
    {
      match = "rem-unlock-srv2";
      alias = "rem-unlock-srv2";
      hostName = "217.160.11.254";
      port = 61343;
      user = "root";
      identityFile = "~/.ssh/srv2";
    }
    {
      match = "rem-srv2";
      alias = "rem-srv2";
      hostName = "217.160.11.254";
      port = 61342;
      user = "h4xx";
      identityFile = "~/.ssh/srv2";
    }
    {
      match = "h4xxsrv1";
      alias = "h4xxsrv1";
      hostName = "10.0.10.152";
      user = "root";
      identityFile = "~/.ssh/personal/h4xxsrv1";
    }
    {
      match = "appddnss";
      alias = "appddnss";
      hostName = "appddnss";
      user = "h4xx";
      identityFile = "~/.ssh/appddnss";
    }
    {
      match = "rem-appddnss";
      alias = "rem-appddnss";
      hostName = "217.160.11.254";
      port = 61341;
      user = "h4xx";
      identityFile = "~/.ssh/appddnss";
    }
    {
      match = "rem-h4xxsrv1";
      alias = "rem-h4xxsrv1";
      hostName = "217.160.11.254";
      port = 61339;
      user = "root";
      identityFile = "~/.ssh/personal/h4xxsrv1";
    }
    {
      match = "unlock-srv1";
      alias = "unlock-srv1";
      hostName = "10.0.10.100";
      port = 6122;
      user = "root";
      identityFile = "~/.ssh/personal/srv1";
    }
    {
      match = "rem-unlock-srv1";
      alias = "rem-unlock-srv1";
      hostName = "217.160.11.254";
      port = 6122;
      user = "root";
      identityFile = "~/.ssh/personal/srv1";
    }
    {
      match = "rem-srv1";
      alias = "rem-srv1";
      hostName = "217.160.11.254";
      port = 61338;
      user = "h4xx";
      identityFile = "~/.ssh/personal/srv1";
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
      match = "labrouter";
      alias = "labrouter";
      hostName = "10.0.11.254";
      user = "root";
      identityFile = "~/.ssh/personal/labrouter";
    }
    {
      match = "router01.h4xx.local";
      alias = "router01.h4xx.local";
      hostName = "10.0.0.1";
      user = "root";
      identityFile = "~/.ssh/personal/router01.h4xx.local";
    }
    {
      match = "suse1";
      alias = "suse1";
      hostName = "10.0.10.155";
      user = "h4xx";
      identityFile = "~/.ssh/suse1";
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
  ];
}
