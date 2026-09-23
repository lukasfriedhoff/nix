{
  "ata-T-FORCE_1TB_TPBF2208240050700434" = {
    host = "srv1";
    purpose = "longhorn";
    luksKeyFile = "luks/srv1-longhorn.txt";
    luksPasswordFile = "/tmp/luks-longhorn.key";
    type = "ssd";
  };
  "ata-T-FORCE_1TB_TPBF2208240050700816" = {
    host = "srv1";
    purpose = "longhorn";
    luksKeyFile = "luks/srv1-longhorn.txt";
    luksPasswordFile = "/tmp/luks-longhorn.key";
    type = "ssd";
  };
  "ata-T-FORCE_1TB_TPBF2209020040601421" = {
    host = "srv1";
    purpose = "longhorn";
    luksKeyFile = "luks/srv1-longhorn.txt";
    luksPasswordFile = "/tmp/luks-longhorn.key";
    type = "ssd";
  };
  "ata-T-FORCE_1TB_TPBF2209020040602776" = {
    host = "srv1";
    purpose = "longhorn";
    luksKeyFile = "luks/srv1-longhorn.txt";
    luksPasswordFile = "/tmp/luks-longhorn.key";
    type = "ssd";
  };
  "ata-T-FORCE_1TB_TPBF2209130010100025" = {
    host = "srv1";
    purpose = "longhorn";
    luksKeyFile = "luks/srv1-longhorn.txt";
    luksPasswordFile = "/tmp/luks-longhorn.key";
    type = "ssd";
  };
  "ata-T-FORCE_1TB_TPBF2209020040602781" = {
    host = "srv8";
    purpose = "longhorn";
    luksKeyFile = "luks/srv8-longhorn.txt";
    luksPasswordFile = "/tmp/luks-longhorn.key";
    type = "ssd";
  };
  # srv2's USB disks (Crucial BX500, Seagate ST4000VX016 and an unlisted
  # SanDisk) were removed 2026-09-24 when the node left the cluster and became
  # the nuc-h4xx-04 workstation. Their Longhorn replicas were evicted to
  # srv1/srv9 first.
  "virtio-srv3-root" = {
    host = "srv3";
    purpose = "root";
    type = "virtual";
  };
  "virtio-srv3-swap" = {
    host = "srv3";
    purpose = "swap";
    type = "virtual";
  };
  "virtio-srv3-longhorn1" = {
    host = "srv3";
    purpose = "longhorn";
    type = "virtual";
  };
  "virtio-srv3-longhorn2" = {
    host = "srv3";
    purpose = "longhorn";
    type = "virtual";
  };
  "virtio-srv5-k3s-stg1-root" = {
    host = "srv5-k3s-stg1";
    purpose = "root";
    type = "virtual";
  };
  "virtio-srv5-k3s-stg1-longhorn1" = {
    host = "srv5-k3s-stg1";
    purpose = "longhorn";
    type = "virtual";
  };
  "virtio-srv6-k3s-stg2-root" = {
    host = "srv6-k3s-stg2";
    purpose = "root";
    type = "virtual";
  };
  "virtio-srv6-k3s-stg2-longhorn1" = {
    host = "srv6-k3s-stg2";
    purpose = "longhorn";
    type = "virtual";
  };
  "virtio-srv7-k3s-stg3-root" = {
    host = "srv7-k3s-stg3";
    purpose = "root";
    type = "virtual";
  };
  "virtio-srv7-k3s-stg3-longhorn1" = {
    host = "srv7-k3s-stg3";
    purpose = "longhorn";
    type = "virtual";
  };
  "ata-WDC_WD40EFRX-68N32N0_WD-WCC7K2FFFP9P" = {
    host = "srv8";
    purpose = "longhorn";
    luksKeyFile = "luks/srv8-longhorn.txt";
    luksPasswordFile = "/tmp/luks-longhorn.key";
    type = "hdd";
  };
  "usb-Seagate_BUP_Slim_BK_NA7WEQ6F-0:0" = {
    host = "srv8";
    purpose = "longhorn";
    luksKeyFile = "luks/srv8-longhorn.txt";
    luksPasswordFile = "/tmp/luks-longhorn.key";
    type = "hdd";
  };
  "ata-ST8000NM0205-2FF112_ZA1J23AK" = {
    host = "srv9";
    purpose = "longhorn";
    luksKeyFile = "luks/srv9-longhorn.txt";
    luksPasswordFile = "/tmp/luks-longhorn.key";
    type = "hdd";
  };
  "ata-ST8000NM0205-2FF112_ZA1J4Q5T" = {
    host = "srv9";
    purpose = "longhorn";
    luksKeyFile = "luks/srv9-longhorn.txt";
    luksPasswordFile = "/tmp/luks-longhorn.key";
    type = "hdd";
  };
  "scsi-35002538b11337b70" = {
    host = "srv9";
    purpose = "longhorn";
    luksKeyFile = "luks/srv9-longhorn.txt";
    luksPasswordFile = "/tmp/luks-longhorn.key";
    type = "ssd";
  };
  "scsi-35002538b11337b80" = {
    host = "srv9";
    purpose = "longhorn";
    luksKeyFile = "luks/srv9-longhorn.txt";
    luksPasswordFile = "/tmp/luks-longhorn.key";
    type = "ssd";
  };
  "scsi-35002538b11337c30" = {
    host = "srv9";
    purpose = "longhorn";
    luksKeyFile = "luks/srv9-longhorn.txt";
    luksPasswordFile = "/tmp/luks-longhorn.key";
    type = "ssd";
  };
  "scsi-35000c500da3a236f" = {
    host = "srv9";
    purpose = "longhorn";
    luksKeyFile = "luks/srv9-longhorn.txt";
    luksPasswordFile = "/tmp/luks-longhorn.key";
    type = "hdd";
  };
  "scsi-35000c500da3339e3" = {
    host = "srv9";
    purpose = "longhorn";
    luksKeyFile = "luks/srv9-longhorn.txt";
    luksPasswordFile = "/tmp/luks-longhorn.key";
    type = "hdd";
  };
}
