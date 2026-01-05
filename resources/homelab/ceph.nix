{
  clusters = {
    homelab = {
      monIp = "10.1.30.5";
      monHosts = [ "ceph.lab.h4xx.io" ];
      monPort = 3300;
      publicNetwork = "10.1.30.0/24";
      bootstrap = {
        singleHostDefaults = true;
        skipDashboard = true;
        extraArgs = [
          "--log-to-file"
          "--no-cleanup-on-failure"
        ];
      };
      pools = [
        {
          name = "images";
          application = "rbd";
          size = 1;
          minSize = 1;
        }
        {
          name = "vmdisks";
          application = "rbd";
          size = 3;
          minSize = 2;
        }
      ];
      kvmPools = [
        {
          name = "ceph-images";
          pool = "images";
          user = "admin";
          secretUuid = "ff27139e-00e7-4e00-9708-5f22e9b94a31";
          keyringFile = "/etc/ceph/ceph.client.admin.keyring";
          confFile = "/etc/ceph/ceph.conf";
          monHost = "ceph.lab.h4xx.io";
          monPort = 3300;
        }
        {
          name = "ceph-vmdisks";
          pool = "vmdisks";
          user = "admin";
          secretUuid = "ff27139e-00e7-4e00-9708-5f22e9b94a31";
          keyringFile = "/etc/ceph/ceph.client.admin.keyring";
          confFile = "/etc/ceph/ceph.conf";
          monHost = "ceph.lab.h4xx.io";
          monPort = 3300;
        }
      ];
    };
  };

  hosts = {
    srv1 = {
      cluster = "homelab";
      roles = [
        "bootstrap"
        "osd"
        "kvm"
      ];
    };
  };
}
