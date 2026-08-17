{
  config,
  inputs,
  lib,
  pkgs,
  secrets,
  ...
}:

let
  hostName = "srv1";
  wolfMoonlightApps = [
    "ui"
    "testBall"
  ];
  wolfBaseApps = [
    "firefox"
    "retroarch"
    "steam"
    "pegasus"
    "lutris"
    "prismlauncher"
    "emulationstation"
    "kodi"
  ];
  wolfGuestApps = wolfBaseApps ++ [
    "desktop"
    "icarusModManager"
  ];
  wolfLukasApps = wolfBaseApps ++ [
    "desktopNix"
    "icarusModManager"
  ];
  allowUnfreePackages = [
    "open-webui"
    "cuda-merged"
    # CUDA toolkit (pkgs.cudaPackages) unfree packages
    "cuda-samples"
    "cuda_cccl"
    "cuda_compat"
    "cuda_crt"
    "cuda_ctadvisor"
    "cuda_cudart"
    "cuda_culibos"
    "cuda_cuobjdump"
    "cuda_cupti"
    "cuda_cuxxfilt"
    "cuda_demo_suite"
    "cuda_documentation"
    "cuda_gdb"
    "cuda_nsight"
    "cuda_nvcc"
    "cuda_nvdisasm"
    "cuda_nvml_dev"
    "cuda_nvprof"
    "cuda_nvprune"
    "cuda_nvrtc"
    "cuda_nvtx"
    "cuda_nvvp"
    "cuda_opencl"
    "cuda_profiler_api"
    "cuda_sanitizer_api"
    "cudatoolkit"
    "cudnn"
    "cuquantum"
    "fabricmanager"
    "imex"
    "libcublas"
    "libcublasmp"
    "libcudla"
    "libcudss"
    "libcufft"
    "libcufile"
    "libcurand"
    "libcusolver"
    "libcusolvermp"
    "libcusparse"
    "libcusparse_lt"
    "libcutensor"
    "libnpp"
    "libnpp_plus"
    "libnvfatbin"
    "libnvjitlink"
    "libnvjpeg"
    "libnvjpeg_2k"
    "libnvptxcompiler"
    "libnvshmem"
    "libnvtiff"
    "libnvvm"
    "nsight_compute"
    "nsight_systems"
    "nvcomp"
    "nvidia_fs"
    "nvpl_blas"
    "nvpl_common"
    "nvpl_fft"
    "nvpl_lapack"
    "nvpl_rand"
    "nvpl_scalapack"
    "nvpl_sparse"
    "nvpl_tensor"
    "tensorrt"
  ];
in
{
  imports = [
    inputs.disko.nixosModules.disko
    ../../common/default.nix
    ../common.nix
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = hostName;
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) allowUnfreePackages;

  homelab.vlanBridges = {
    enable = true;
    uplink = "eno1";
    mgmtMac = "0c:c4:7a:6c:38:02";
    # Silent drift (kept on purpose for now): srv1 never received the netdev
    # MAC pin nor the RouteMetric/static-route networkd blocks that
    # srv2/srv8/srv9 carry. Flip these to true once srv1's routing has been
    # verified against the other hosts.
    pinBridgeMac = false;
    routeMetrics = false;
  };

  homelab.personalServer = {
    enable = true;
    managementPubKey = "ssh/srv1-personal-mgmt.pub";
    usePasswordAuth = false;
  };

  sops.secrets."srv1-comin-builder-key" = {
    sopsFile = "${secrets.primary}/ssh/srv1-comin-builder.priv";
    owner = "root";
    format = "binary";
    mode = "0400";
    path = "/root/.ssh/srv1-comin-builder";
  };

  sops.secrets."srv1-comin-builder-pub" = {
    sopsFile = "${secrets.primary}/ssh/srv1-comin-builder.pub";
    owner = "root";
    format = "binary";
    mode = "0444";
    path = "/root/.ssh/srv1-comin-builder.pub";
  };

  services.openssh.authorizedKeysFiles = lib.mkAfter [
    config.sops.secrets."srv1-comin-builder-pub".path
  ];

  lukasf.remoteBuilds.sshKeyFile = config.sops.secrets."srv1-comin-builder-key".path;

  lukasf.nixCache = {
    enable = true;
    secretKeyFile = "nix-cache/nix-serve.key";
    publicKey = builtins.readFile ../../../resources/nix-cache/personal-cache.pub;
    openFirewall = true;
    configureClient = true;
    # Use loopback locally to avoid depending on the DHCP-assigned mgmt IP during builds.
    cacheUrl = "http://127.0.0.1:5000";
  };

  lukasf.serverDeployment.enableComin = true;

  lukasf.seaweedfs.enable = false;

  lukasf.ollama = {
    enable = true;
    host = "0.0.0.0";
    acceleration = "rocm";
    rocmOverrideGfx = "11.0.0"; # AMD 7900 XTX (RDNA3/gfx1100)
    environmentVariables = {
      OLLAMA_LLM_LIBRARY = "rocm";
      OLLAMA_NUM_GPU = "1";
      OLLAMA_LOAD_TIMEOUT = "10m";
    };
    openFirewall = true;
    ui = {
      enable = true;
      ollamaUrl = "http://10.1.30.12:11434";
    };
  };

  lukasf.openWebui = {
    host = "0.0.0.0";
    port = 8081;
    openFirewall = true;
  };

  lukasf.wolf = {
    enable = true;
    openFirewall = true;
    appImages = [
      {
        name = "localhost/wolf-icarus-mod-manager:latest";
        dockerfile = ../../../containers/wolf-icarus-mod-manager/Dockerfile;
        context = ../../../containers/wolf-icarus-mod-manager;
      }
    ];
    appImageArchives = [
      {
        name = "localhost/wolf-desktop-nix:latest";
        archive = inputs.self.nixosConfigurations.virtual-05-container.config.system.build.tarball;
        format = "import";
      }
    ];
    appCatalog.desktopNix = {
      title = "Desktop (Nix - lukasf)";
      icon_png_path = "https://games-on-whales.github.io/wildlife/apps/xfce/assets/icon.png";
      app_state_folder = "desktop-nix";
      runner = {
        type = "docker";
        name = "WolfDesktopNix";
        image = "localhost/wolf-desktop-nix:latest";
        mounts = [ ];
        env = [
          "UNAME=lukasf"
          "PUID=1000"
          "PGID=1000"
          "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
        ];
        devices = [ ];
        ports = [ ];
        base_create_json = ''
          {
            "HostConfig": {
              "IpcMode": "host",
              "Privileged": false,
              "CapAdd": ["SYS_ADMIN", "SYS_NICE", "SYS_PTRACE", "NET_RAW", "MKNOD", "NET_ADMIN"],
              "SecurityOpt": ["seccomp=unconfined", "apparmor=unconfined"],
              "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
            }
          }
        '';
      };
    };
    settings = {
      hostname = "Wolf";
      config_version = 6;
    };
    profiles = [
      {
        id = "moonlight-profile-id";
        appNames = wolfMoonlightApps;
      }
      {
        id = "lukas";
        name = "Lukas";
        appNames = wolfLukasApps;
      }
      {
        id = "guest";
        name = "Guest";
        appNames = wolfGuestApps;
      }
    ];
  };

  lukasf.kvm.enable = true;

  # GitHub PAT for Flux GitOps
  sops.secrets."flux-cluster-token" = {
    sopsFile = "${secrets.profileShared}/homelab/flux-cluster-dev/flux-cluster-bootstrap-token.txt";
    owner = "root";
    format = "binary";
    mode = "0400";
  };

  # Enable k3s with Flux GitOps
  homelab.kubernetes = {
    enable = true;
    tlsSans = [
      "srv1.lab.h4xx.io"
      "srv1"
      "10.1.30.12"
    ];
    gitops = {
      enable = true;
      repoURL = "https://github.com/lukasfriedhoff/flux-cluster.git";
      branch = "main";
      path = "./overlays/homelab";
      tokenFile = config.sops.secrets."flux-cluster-token".path;
      username = "lukasfriedhoff";
      sourceName = "flux-cluster";
      kustomizationName = "homelab";
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  sops.age.keyFile = "/var/lib/sops-nix/age/keys.txt";

  homelab.initrdSsh = {
    enable = true;
    authorizedKeyFile = ./initrd-authorized.pub;
  };

  environment.systemPackages = with pkgs; [
    nvtopPackages.full
  ];

  networking.firewall.allowedTCPPorts = [ 4243 ];

  networking.extraHosts = ''
    # srv1 srv1.lab.h4xx.io 10.1.30.12
  '';

}
