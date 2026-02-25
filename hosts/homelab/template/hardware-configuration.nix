_:

{
  assertions = [
    {
      assertion = false;
      message = "Replace hosts/homelab/<name>/hardware-configuration.nix with the generated file from the installer (`nixos-generate-config --show-hardware-config`).";
    }
  ];
}
