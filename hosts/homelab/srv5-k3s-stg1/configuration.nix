{ ... }:

{
  imports = [
    (import ../k3s-staging/node.nix {
      authorizedKeyFile = ./initrd-authorized.pub;
      bootstrap = true;
      macAddress = "52:54:00:be:0f:f4";
      nodeIP = "10.1.30.18";
      nodeName = "srv5-k3s-stg1";
    })
  ];
}
