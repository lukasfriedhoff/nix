{ ... }:

{
  imports = [
    (import ../k3s-staging/node.nix {
      authorizedKeyFile = ./initrd-authorized.pub;
      bootstrap = false;
      longhornBind = true;
      macAddress = "52:54:00:0b:b2:6c";
      nodeIP = "10.1.30.19";
      nodeName = "srv6-k3s-stg2";
    })
  ];
}
