{ ... }:

{
  imports = [
    (import ../testingrke2/node.nix {
      authorizedKeyFile = ./initrd-authorized.pub;
      bootstrap = false;
      macAddress = "52:54:00:72:6b:13";
      nodeIndex = 3;
      nodeIP = "192.168.124.13";
      nodeName = "testingrke2-03";
      priority = 110;
    })
  ];
}
