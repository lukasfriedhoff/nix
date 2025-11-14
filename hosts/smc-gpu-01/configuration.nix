{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/hardware/supermicro/amd7900xtx.nix
  ];

  networking.hostName = "smc-gpu-01";

  homelab.kubernetes = {
    enable = true;
    extraK3sFlags = [
      "--cluster-init"
      "--tls-san smc-gpu-01"
    ];
    gitops = {
      enable = true;
      repoURL = "ssh://git@github.com/lukasfriedhoff/gitops.git"; # adjust to your GitOps repo
      path = "./clusters/smc-gpu-01";
      sshKeyFile = "smc-gpu-01/flux/id_ed25519";
    };
  };

  homelab.gitops = {
    enable = true;
    repoURL = "ssh://git@github.com/lukasfriedhoff/nix.git";
    branch = "main";
    flakeAttr = "smc-gpu-01";
    sshKeyFile = "smc-gpu-01/gitops/id_ed25519";
    interval = "10m";
  };

  # GPU workloads often benefit from hugepages
  boot.kernelParams = [
    "default_hugepagesz=1G"
    "hugepagesz=1G"
    "hugepages=8"
  ];

  services.openssh.enable = true;
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  nixpkgs.config.allowUnfree = true;

  users.users.lukasf = {
    isNormalUser = true;
    description = "Lukas Friedhoff";
    extraGroups = [
      "wheel"
      "docker"
    ];
    openssh.authorizedKeys.keys = [ ];
  };
  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    helmfile
    kubernetes-helm
  ];
}
