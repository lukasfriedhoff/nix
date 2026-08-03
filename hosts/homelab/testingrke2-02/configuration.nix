{ ... }:

{
  imports = [
    (import ../testingrke2/node.nix {
      authorizedKeyFile = ./initrd-authorized.pub;
      bootstrap = false;
      macAddress = "52:54:00:72:6b:12";
      nodeIndex = 2;
      nodeIP = "192.168.124.12";
      nodeName = "testingrke2-02";
      priority = 120;
    })
  ];
}
