{ ... }:

{
  imports = [
    (import ../k3s-staging/node.nix {
      authorizedKeyFile = ./initrd-authorized.pub;
      bootstrap = false;
      macAddress = "52:54:00:00:49:eb";
      nodeIP = "10.1.30.22";
      nodeName = "srv7-k3s-stg3";
    })
  ];
}
