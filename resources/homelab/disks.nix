{
  "ata-T-FORCE_1TB_TPBF2208240050700434" = {
    host = "srv1";
    purpose = "ceph";
    lockboxKeyFile = "83897024-e964-11f0-9d5c-0cc47a6c3802/osd-lockbox/ata-T-FORCE_1TB_TPBF2208240050700434.key";
    type = "ssd";
  };
  "ata-T-FORCE_1TB_TPBF2208240050700816" = {
    host = "srv1";
    purpose = "ceph";
    lockboxKeyFile = "83897024-e964-11f0-9d5c-0cc47a6c3802/osd-lockbox/ata-T-FORCE_1TB_TPBF2208240050700816.key";
    type = "ssd";
  };
  "ata-T-FORCE_1TB_TPBF2209020040601421" = {
    host = "srv1";
    purpose = "ceph";
    lockboxKeyFile = "83897024-e964-11f0-9d5c-0cc47a6c3802/osd-lockbox/ata-T-FORCE_1TB_TPBF2209020040601421.key";
    type = "ssd";
  };
  "ata-T-FORCE_1TB_TPBF2209020040602776" = {
    host = "srv1";
    purpose = "ceph";
    lockboxKeyFile = "83897024-e964-11f0-9d5c-0cc47a6c3802/osd-lockbox/ata-T-FORCE_1TB_TPBF2209020040602776.key";
    type = "ssd";
  };
  "ata-T-FORCE_1TB_TPBF2209130010100025" = {
    host = "srv1";
    purpose = "ceph";
    lockboxKeyFile = "83897024-e964-11f0-9d5c-0cc47a6c3802/osd-lockbox/ata-T-FORCE_1TB_TPBF2209130010100025.key";
    type = "ssd";
  };
  "ata-T-FORCE_1TB_TPBF2209020040602781" = {
    host = "srv2";
    purpose = "mdadm";
    luksKeyFile = "luks/srv2-mdraid.txt";
    luksPasswordFile = "/tmp/luks-mdraid.key";
    type = "ssd";
  };
  "ata-CT1000BX500SSD1_2216E629C77B" = {
    host = "srv2";
    purpose = "mdadm";
    luksKeyFile = "luks/srv2-mdraid.txt";
    luksPasswordFile = "/tmp/luks-mdraid.key";
    type = "ssd";
  };
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
  "virtio-srv3-ceph1" = {
    host = "srv3";
    purpose = "ceph";
    type = "virtual";
  };
  "virtio-srv3-ceph2" = {
    host = "srv3";
    purpose = "ceph";
    type = "virtual";
  };
  "virtio-srv3-ceph3" = {
    host = "srv3";
    purpose = "ceph";
    type = "virtual";
  };
  "virtio-srv3-longhorn1" = {
    host = "srv3";
    purpose = "longhorn";
    type = "virtual";
  };
  "ata-ST4000VX016-3CV104_WW60911A" = {
    host = "srv2";
    purpose = "storage";
    type = "hdd";
  };
  "ata-WDC_WD40EFRX-68N32N0_WD-WCC7K2FFFP9P" = {
    host = "srv2";
    purpose = "storage";
    type = "hdd";
  };
}
