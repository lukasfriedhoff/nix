# smc-gpu-01 (Supermicro + Radeon 7900 XTX)

- **Platform**: Supermicro bare-metal server with IPMI BMC.
- **CPU**: Recent AMD EPYC/Threadripper (enable `kvm-amd`).
- **GPU**: Radeon RX 7900 XTX (RDNA3). The hardware module
  `modules/nixos/hardware/supermicro/amd7900xtx.nix` enables amdgpu, firmware,
  ROCm utilities (`rocm-smi`), and power/performance knobs.
- **Management**: IPMI enabled via `services.ipmi`.
- **Kubernetes**: Single-node k3s control plane with Flux GitOps bootstrap.
- **GitOps**: Flux uses an SSH deploy key stored under
  `secrets/personal/smc-gpu-01/flux/id_ed25519`. Adjust `repoURL`/`path` in
  `hosts/smc-gpu-01/configuration.nix` to match your manifests.
  The host itself also performs NixOS GitOps via `homelab.gitops`, which clones
  this repository on a timer and runs `nixos-rebuild switch --flake ...`. Place
  the deploy key at `secrets/personal/smc-gpu-01/gitops/id_ed25519`.

## Bring-up Steps

1. Run `nixos-generate-config` on the host and overwrite
   `hosts/smc-gpu-01/hardware-configuration.nix`.
2. Place the Flux deploy key in `secrets/personal/smc-gpu-01/flux/id_ed25519`
   and re-encrypt with SOPS.
3. Update `homelab.kubernetes.gitops.repoURL`/`path` if you use a different Git
   repository.
4. Deploy with `sudo nixos-rebuild switch --flake .#smc-gpu-01`.
