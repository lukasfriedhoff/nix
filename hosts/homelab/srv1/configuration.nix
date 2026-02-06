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
  homelabDisks = import ../../../resources/homelab/disks.nix;
  nets = import ../../../resources/homelab/networks.nix;
  cephTopology = import ../../../resources/homelab/ceph.nix;
  cephHost = cephTopology.hosts.${hostName};
  cephCluster = cephTopology.clusters.${cephHost.cluster};
  cephRoles = cephHost.roles;
  hasRole = role: lib.elem role cephRoles;
  cephDiskEntries = lib.filterAttrs (_: v: v.host == hostName && v.purpose == "ceph") homelabDisks;
  cephDisks = map (diskId: "/dev/disk/by-id/${diskId}") (lib.attrNames cephDiskEntries);
  cephLockboxKeys =
    lib.mapAttrsToList
      (diskId: disk: {
        device = "/dev/disk/by-id/${diskId}";
        secretKeyFile = disk.lockboxKeyFile;
      })
      (
        lib.filterAttrs (_: v: v.host == hostName && v.purpose == "ceph" && v ? lockboxKeyFile) homelabDisks
      );
  wolfUiApp = {
    title = "Wolf UI";
    icon_png_path = "https://raw.githubusercontent.com/games-on-whales/wolf-ui/refs/heads/main/src/Icons/wolf_ui_icon.png";
    start_virtual_compositor = true;
    runner = {
      type = "docker";
      name = "Wolf-UI";
      image = "ghcr.io/games-on-whales/wolf-ui:main";
      mounts = [
        "/var/run/wolf/wolf.sock:/var/run/wolf/wolf.sock"
      ];
      env = [
        "GOW_REQUIRED_DEVICES=/dev/input/event* /dev/dri/* /dev/nvidia*"
        "WOLF_SOCKET_PATH=/var/run/wolf/wolf.sock"
        "WOLF_UI_AUTOUPDATE=False"
        "LOGLEVEL=INFO"
      ];
      devices = [ ];
      ports = [ ];
      base_create_json = ''
        {
          "HostConfig": {
            "IpcMode": "host",
            "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_ADMIN", "SYS_NICE"],
            "Privileged": false,
            "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
          }
        }
      '';
    };
  };
  wolfTestBallApp = {
    title = "Test ball";
    icon_png_path = "https://raw.githubusercontent.com/games-on-whales/wolf/refs/heads/stable/docs/images/test_ball_icon.png";
    start_audio_server = false;
    start_virtual_compositor = false;
    runner = {
      type = "process";
      run_cmd = "sh -c \"while :; do echo 'running...'; sleep 10; done\"";
    };
    audio = {
      source = "audiotestsrc wave=ticks is-live=true";
    };
    video = {
      source = "videotestsrc pattern=ball flip=true is-live=true !\nvideo/x-raw, framerate={fps}/1\n";
    };
  };
  wolfFirefoxApp = {
    title = "Firefox";
    icon_png_path = "https://games-on-whales.github.io/wildlife/apps/firefox/assets/icon.png";
    start_virtual_compositor = true;
    runner = {
      type = "docker";
      name = "WolfFirefox";
      image = "ghcr.io/games-on-whales/firefox:edge";
      mounts = [ ];
      env = [
        "RUN_SWAY=1"
        "MOZ_ENABLE_WAYLAND=1"
        "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
      ];
      devices = [ ];
      ports = [ ];
      base_create_json = ''
        {
          "HostConfig": {
            "IpcMode": "host",
            "Privileged": false,
            "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN"],
            "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
          }
        }
      '';
    };
  };
  wolfRetroarchApp = {
    title = "RetroArch";
    icon_png_path = "https://games-on-whales.github.io/wildlife/apps/retroarch/assets/icon.png";
    start_virtual_compositor = true;
    runner = {
      type = "docker";
      name = "WolfRetroarch";
      image = "ghcr.io/games-on-whales/retroarch:edge";
      mounts = [ ];
      env = [
        "RUN_SWAY=true"
        "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
      ];
      devices = [ ];
      ports = [ ];
      base_create_json = ''
        {
          "HostConfig": {
            "IpcMode": "host",
            "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_ADMIN", "SYS_NICE"],
            "Privileged": false,
            "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
          }
        }
      '';
    };
  };
  wolfSteamApp = {
    title = "Steam";
    icon_png_path = "https://games-on-whales.github.io/wildlife/apps/steam/assets/icon.png";
    start_virtual_compositor = true;
    runner = {
      type = "docker";
      name = "WolfSteam";
      image = "ghcr.io/games-on-whales/steam:edge";
      mounts = [ ];
      env = [
        "PROTON_LOG=1"
        "RUN_SWAY=true"
        "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
      ];
      devices = [ ];
      ports = [ ];
      base_create_json = ''
        {
          "HostConfig": {
            "IpcMode": "host",
            "CapAdd": ["SYS_ADMIN", "SYS_NICE", "SYS_PTRACE", "NET_RAW", "MKNOD", "NET_ADMIN"],
            "SecurityOpt": ["seccomp=unconfined", "apparmor=unconfined"],
            "Ulimits": [{"Name":"nofile", "Hard":10240, "Soft":10240}],
            "Privileged": false,
            "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
          }
        }
      '';
    };
  };
  wolfPegasusApp = {
    title = "Pegasus";
    icon_png_path = "https://games-on-whales.github.io/wildlife/apps/pegasus/assets/icon.png";
    start_virtual_compositor = true;
    runner = {
      type = "docker";
      name = "WolfPegasus";
      image = "ghcr.io/games-on-whales/pegasus:edge";
      mounts = [ ];
      env = [
        "RUN_SWAY=1"
        "GOW_REQUIRED_DEVICES=/dev/input/event* /dev/dri/* /dev/nvidia*"
      ];
      devices = [ ];
      ports = [ ];
      base_create_json = ''
        {
          "HostConfig": {
            "IpcMode": "host",
            "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_ADMIN", "SYS_NICE"],
            "Privileged": false,
            "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
          }
        }
      '';
    };
  };
  wolfLutrisApp = {
    title = "Lutris";
    icon_png_path = "https://games-on-whales.github.io/wildlife/apps/lutris/assets/icon.png";
    start_virtual_compositor = true;
    runner = {
      type = "docker";
      name = "WolfLutris";
      image = "ghcr.io/games-on-whales/lutris:edge";
      mounts = [
        "lutris:/var/lutris/:rw"
      ];
      env = [
        "RUN_SWAY=1"
        "GOW_REQUIRED_DEVICES=/dev/input/event* /dev/dri/* /dev/nvidia* /var/lutris/"
      ];
      devices = [ ];
      ports = [ ];
      base_create_json = ''
        {
          "HostConfig": {
            "IpcMode": "host",
            "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_ADMIN", "SYS_NICE"],
            "Privileged": false,
            "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
          }
        }
      '';
    };
  };
  wolfPrismlauncherApp = {
    title = "Prismlauncher";
    icon_png_path = "https://games-on-whales.github.io/wildlife/apps/prismlauncher/assets/icon.png";
    start_virtual_compositor = true;
    runner = {
      type = "docker";
      name = "Prismlauncher";
      image = "ghcr.io/games-on-whales/prismlauncher:edge";
      mounts = [ ];
      env = [
        "RUN_SWAY=1"
        "GOW_REQUIRED_DEVICES=/dev/input/event* /dev/dri/* /dev/nvidia* /var/lutris/"
      ];
      devices = [ ];
      ports = [ ];
      base_create_json = ''
        {
          "HostConfig": {
            "IpcMode": "host",
            "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN", "SYS_ADMIN", "SYS_NICE"],
            "Privileged": false,
            "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
          }
        }
      '';
    };
  };
  wolfDesktopApp = {
    title = "Desktop (xfce)";
    icon_png_path = "https://games-on-whales.github.io/wildlife/apps/xfce/assets/icon.png";
    runner = {
      type = "docker";
      name = "WolfXFCE";
      image = "ghcr.io/games-on-whales/xfce:edge";
      mounts = [ ];
      env = [
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
  wolfEmulationStationApp = {
    title = "EmulationStation";
    icon_png_path = "https://games-on-whales.github.io/wildlife/apps/es-de/assets/icon.png";
    runner = {
      type = "docker";
      name = "WolfES-DE";
      image = "ghcr.io/games-on-whales/es-de:edge";
      mounts = [ ];
      env = [
        "RUN_SWAY=1"
        "MOZ_ENABLE_WAYLAND=1"
        "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
      ];
      devices = [ ];
      ports = [ ];
      base_create_json = ''
        {
          "HostConfig": {
            "IpcMode": "host",
            "Privileged": false,
            "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN"],
            "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
          }
        }
      '';
    };
  };
  wolfKodiApp = {
    title = "Kodi";
    icon_png_path = "https://games-on-whales.github.io/wildlife/apps/kodi/assets/icon.png";
    runner = {
      type = "docker";
      name = "WolfKodi";
      image = "ghcr.io/games-on-whales/kodi:edge";
      mounts = [ ];
      env = [
        "RUN_SWAY=true"
        "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
      ];
      devices = [ ];
      ports = [ ];
      base_create_json = ''
        {
          "HostConfig": {
            "IpcMode": "host",
            "Privileged": false,
            "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN"],
            "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
          }
        }
      '';
    };
  };
  wolfIcarusModManagerApp = {
    title = "Icarus Mod Manager";
    start_virtual_compositor = true;
    app_state_folder = "icarus-mod-manager";
    runner = {
      type = "docker";
      name = "WolfIcarusModManager";
      image = "localhost/wolf-icarus-mod-manager:latest";
      mounts = [ ];
      env = [
        "RUN_SWAY=1"
        "GOW_REQUIRED_DEVICES=/dev/input/* /dev/dri/* /dev/nvidia*"
      ];
      devices = [ ];
      ports = [ ];
      base_create_json = ''
        {
          "HostConfig": {
            "IpcMode": "host",
            "Privileged": false,
            "CapAdd": ["NET_RAW", "MKNOD", "NET_ADMIN"],
            "DeviceCgroupRules": ["c 13:* rmw", "c 244:* rmw"]
          }
        }
      '';
    };
  };
  wolfMoonlightApps = [
    wolfUiApp
    wolfTestBallApp
  ];
  wolfBaseApps = [
    wolfFirefoxApp
    wolfRetroarchApp
    wolfSteamApp
    wolfPegasusApp
    wolfLutrisApp
    wolfPrismlauncherApp
    wolfDesktopApp
    wolfEmulationStationApp
    wolfKodiApp
  ];
  wolfUserApps = wolfBaseApps ++ [
    wolfIcarusModManagerApp
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
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  networking.defaultGateway = lib.mkForce null;
  networking.nameservers = [ "10.1.30.1" ];
  # DHCP should run on the bridge (brvlan30), not on the slave.
  networking.interfaces.eno1.useDHCP = lib.mkForce false;
  networking.vlans = {
    "eno1.20" = {
      id = nets.vlans.server.id;
      interface = "eno1";
    };
    "eno1.40" = {
      id = nets.vlans.storage.id;
      interface = "eno1";
    };
    "eno1.10" = {
      id = nets.vlans.lan.id;
      interface = "eno1";
    };
    "eno1.12" = {
      id = nets.vlans.iot.id;
      interface = "eno1";
    };
    "eno1.13" = {
      id = nets.vlans.windows.id;
      interface = "eno1";
    };
    "eno1.50" = {
      id = nets.vlans.lab.id;
      interface = "eno1";
    };
  };

  # Bring VLAN subinterfaces up even without an IP so bridges attach cleanly.
  networking.interfaces."eno1.20".useDHCP = false;
  networking.interfaces."eno1.40".useDHCP = false;
  networking.interfaces."eno1.10".useDHCP = false;
  networking.interfaces."eno1.12".useDHCP = false;
  networking.interfaces."eno1.13".useDHCP = false;
  networking.interfaces."eno1.50".useDHCP = false;

  # Libvirt-friendly bridges for each VLAN (mgmt on brvlan30).
  networking.bridges = {
    brvlan10.interfaces = [ "eno1.10" ];
    brvlan12.interfaces = [ "eno1.12" ];
    brvlan13.interfaces = [ "eno1.13" ];
    brvlan20.interfaces = [ "eno1.20" ];
    brvlan30.interfaces = [ "eno1" ]; # untagged mgmt
    brvlan40.interfaces = [ "eno1.40" ];
    brvlan50.interfaces = [ "eno1.50" ];
  };
  networking.interfaces.brvlan30 = {
    useDHCP = true;
  };
  networking.interfaces.brvlan20.useDHCP = true;
  networking.interfaces.brvlan40.useDHCP = true;
  networking.hosts = {
    "127.0.0.2" = lib.mkForce [ ];
  };

  # Use MAC-based DHCP client ID on the management bridge so the reservation matches eno1.
  systemd.network.networks."30-brvlan30" = {
    matchConfig.Name = "brvlan30";
    networkConfig.DHCP = "yes";
    dhcpV4Config.ClientIdentifier = "mac";
  };
  systemd.network.netdevs."40-brvlan30" = {
    netdevConfig = {
      Name = "brvlan30";
      Kind = "bridge";
      MACAddress = "0c:c4:7a:6c:38:02";
    };
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
    openFirewall = true;
    ui = {
      enable = true;
      host = "0.0.0.0";
      port = 8081;
      openFirewall = true;
      ollamaUrl = "http://10.1.30.12:11434";
    };
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
    settings = {
      hostname = "Wolf";
      config_version = 6;
      profiles = [
        {
          id = "moonlight-profile-id";
          apps = wolfMoonlightApps;
        }
        {
          id = "lukas";
          name = "Lukas";
          apps = wolfUserApps;
        }
        {
          id = "guest";
          name = "Guest";
          apps = wolfUserApps;
        }
      ];
    };
  };

  lukasf.ceph = {
    enable = true;
    monHosts = cephCluster.monHosts or [ cephCluster.monIp ];
    monPort = cephCluster.monPort or 3300;
    bootstrap = {
      enable = hasRole "bootstrap";
      fsid = cephCluster.fsid;
      monIp = cephCluster.monIp;
      publicNetwork = cephCluster.publicNetwork;
      singleHostDefaults = cephCluster.bootstrap.singleHostDefaults;
      skipDashboard = cephCluster.bootstrap.skipDashboard;
      extraArgs = cephCluster.bootstrap.extraArgs;
    };
    pools = lib.optionals (hasRole "bootstrap") cephCluster.pools;
    backup = lib.mkIf (hasRole "bootstrap") {
      enable = cephCluster.backup.enable or false;
      secretKeyFile = cephCluster.backup.secretKeyFile or null;
      retentionDays = cephCluster.backup.retentionDays or 30;
      schedule = cephCluster.backup.schedule or "daily";
    };
    osd = {
      devices = cephDisks;
      lockboxKeys = cephLockboxKeys;
      provisioner = "ceph-volume";
      encrypted = true;
      autoProvision = hasRole "osd";
      zapDevices = false;
    };
    monUpdate = {
      enable = hasRole "bootstrap";
      name = hostName;
      address = cephCluster.monIp;
      legacyAddress = "10.1.30.5";
    };
    healthCheck = {
      enable = true;
      checkLibvirt = hasRole "kvm";
      libvirtPools = [
        "ceph-images"
        "ceph-vmdisks"
      ];
    };
  };

  lukasf.ceph.client = lib.mkIf (hasRole "kvm") {
    enable = true;
    fsid = cephCluster.fsid or null;
    publicNetwork = cephCluster.publicNetwork or null;
  };

  lukasf.kvm = lib.mkIf (hasRole "kvm") {
    enable = true;
    storage = {
      backend = "ceph";
      ceph.pools = cephCluster.kvmPools;
    };
  };

  # Ensure QEMU has Ceph/RBD support for libvirt pools when KVM role is enabled.
  virtualisation.libvirtd.qemu.package = lib.mkIf (hasRole "kvm") (
    lib.mkForce (pkgs.qemu_kvm.override { cephSupport = true; })
  );

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
    extraK3sFlags = [
      "--tls-san srv1.lab.h4xx.io"
      "--tls-san srv1"
      "--tls-san 10.1.30.12"
    ];
    gitops = {
      enable = true;
      repoURL = "https://github.com/lukasfriedhoff/flux-cluster.git";
      branch = "develop";
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

  # Needed by cephadm to satisfy asyncssh dependency for health checks.
  environment.systemPackages = with pkgs; [
    python3Packages.asyncssh
    nvtopPackages.full
  ];

  networking.firewall.allowedTCPPorts = [ 4243 ];

  networking.extraHosts = ''
    # srv1 srv1.lab.h4xx.io 10.1.30.12
  '';

}
