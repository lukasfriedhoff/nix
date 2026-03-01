{
  clusters = {
    homelab = {
      fsid = "83897024-e964-11f0-9d5c-0cc47a6c3802";
      monIp = "10.1.30.12";
      monHosts = [ "srv1.lab.h4xx.io" ];
      monPort = 3300;
      publicNetwork = "10.1.30.0/24";
      backup = {
        enable = true;
        secretKeyFile = "83897024-e964-11f0-9d5c-0cc47a6c3802/backup.key";
        retentionDays = 30;
        schedule = "daily";
      };
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
        # Kubernetes RBD pools
        {
          name = "k8s-ssd-1r";
          application = "rbd";
          size = 1;
          minSize = 1;
        }
        {
          name = "k8s-ssd-2r";
          application = "rbd";
          size = 2;
          minSize = 1;
        }
        {
          name = "k8s-ssd-3r";
          application = "rbd";
          size = 3;
          minSize = 2;
        }
      ];
      cephfs = [
        {
          name = "ssd-cephfs";
          metadataPool = {
            name = "ssd-cephfs-meta-3r";
            size = 3;
            minSize = 2;
          };
          dataPools = [
            {
              name = "ssd-cephfs-1r";
              size = 1;
              minSize = 1;
            }
            {
              name = "ssd-cephfs-2r";
              size = 2;
              minSize = 1;
            }
            {
              name = "ssd-cephfs-3r";
              size = 3;
              minSize = 2;
            }
          ];
          mds = {
            count = 1;
          };
        }
      ];
      rgw = {
        enable = true;
        serviceId = "homelab";
        realm = "homelab";
        zonegroup = "homelab";
        zone = "homelab";
        endpoint = "http://srv1.lab.h4xx.io:7480";
        region = "us-east-1";
        poolPrefix = "homelab";
        pool = {
          size = 1;
          minSize = 1;
        };
        bucketPrefix = "homelab";
        users = [
          {
            name = "homelab-lgtm";
            displayName = "Homelab LGTM";
            accessKeyFile = "83897024-e964-11f0-9d5c-0cc47a6c3802/rgw/homelab-lgtm.access.key";
            secretKeyFile = "83897024-e964-11f0-9d5c-0cc47a6c3802/rgw/homelab-lgtm.secret.key";
          }
        ];
        buckets = [
          {
            name = "loki";
            user = "homelab-lgtm";
          }
          {
            name = "mimir-blocks";
            user = "homelab-lgtm";
          }
          {
            name = "mimir-alertmanager";
            user = "homelab-lgtm";
          }
          {
            name = "mimir-ruler";
            user = "homelab-lgtm";
          }
          {
            name = "tempo";
            user = "homelab-lgtm";
          }
        ];
      };
      kvmPools = [
        {
          name = "ceph-images";
          pool = "images";
          user = "admin";
          secretUuid = "ff27139e-00e7-4e00-9708-5f22e9b94a31";
          keyringFile = "/etc/ceph/ceph.client.admin.keyring";
          confFile = "/etc/ceph/ceph.conf";
          monHost = "srv1.lab.h4xx.io";
          monPort = 3300;
        }
        {
          name = "ceph-vmdisks";
          pool = "vmdisks";
          user = "admin";
          secretUuid = "ff27139e-00e7-4e00-9708-5f22e9b94a31";
          keyringFile = "/etc/ceph/ceph.client.admin.keyring";
          confFile = "/etc/ceph/ceph.conf";
          monHost = "srv1.lab.h4xx.io";
          monPort = 3300;
        }
      ];
    };

    testing = {
      fsid = "5bb51195-8104-49cb-ad7c-a7cb6a7bfb1c";
      # Local libvirt lease IP for srv3 (update if lease changes).
      monIp = "192.168.122.243";
      monHosts = [ "192.168.122.243" ];
      monPort = 3300;
      publicNetwork = "192.168.122.0/24";
      backup = {
        enable = false;
      };
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
          name = "testing-images";
          application = "rbd";
          size = 1;
          minSize = 1;
        }
        {
          name = "testing-vmdisks";
          application = "rbd";
          size = 1;
          minSize = 1;
        }
        {
          name = "testing-k8s-ssd-1r";
          application = "rbd";
          size = 1;
          minSize = 1;
        }
        {
          name = "testing-k8s-ssd-2r";
          application = "rbd";
          size = 1;
          minSize = 1;
        }
        {
          name = "testing-k8s-ssd-3r";
          application = "rbd";
          size = 1;
          minSize = 1;
        }
      ];
      cephfs = [
        {
          name = "testing-ssd-cephfs";
          metadataPool = {
            name = "testing-ssd-cephfs-meta-1r";
            size = 1;
            minSize = 1;
          };
          dataPools = [
            {
              name = "testing-ssd-cephfs-1r";
              size = 1;
              minSize = 1;
            }
            {
              name = "testing-ssd-cephfs-2r";
              size = 1;
              minSize = 1;
            }
            {
              name = "testing-ssd-cephfs-3r";
              size = 1;
              minSize = 1;
            }
          ];
          mds = {
            count = 1;
          };
        }
      ];
      rgw = {
        enable = false;
      };
      kvmPools = [
        {
          name = "testing-ceph-images";
          pool = "testing-images";
          user = "admin";
          secretUuid = "3ddfbba6-8046-4d3e-a18b-1f2542002865";
          keyringFile = "/etc/ceph/ceph.client.admin.keyring";
          confFile = "/etc/ceph/ceph.conf";
          monHost = "192.168.122.243";
          monPort = 3300;
        }
        {
          name = "testing-ceph-vmdisks";
          pool = "testing-vmdisks";
          user = "admin";
          secretUuid = "3ddfbba6-8046-4d3e-a18b-1f2542002865";
          keyringFile = "/etc/ceph/ceph.client.admin.keyring";
          confFile = "/etc/ceph/ceph.conf";
          monHost = "192.168.122.243";
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

    srv3 = {
      cluster = "testing";
      roles = [
        "bootstrap"
        "osd"
        "kvm"
      ];
    };
  };
}
