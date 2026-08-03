{ ... }:

{
  imports = [
    (import ../testingrke2/node.nix {
      authorizedKeyFile = ./initrd-authorized.pub;
      bootstrap = true;
      macAddress = "52:54:00:72:6b:11";
      nodeIndex = 1;
      nodeIP = "192.168.124.11";
      nodeName = "testingrke2-01";
      priority = 130;
    })
  ];
}
