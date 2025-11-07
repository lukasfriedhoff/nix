# Gaming Optimizations – tux-h4xx-01

Hardware recap: Intel Iris Xe iGPU + NVIDIA RTX 4070 Max-Q (PRIME offload), 2560×1600 165 Hz panel. These tweaks target Proton titles (especially Unreal Engine 4/5) and Steam on Linux.

## Stack Overview

- `programs.steam.enable` with Proton-GE (GE-Proton9-12) for better UE4/DX12 support.
- `programs.gamemode` boosts CPU scheduler priority and applies NVIDIA performance levels.
- `programs.gamescope` exposes a forced fullscreen compositor (1080p@165 Hz, HDR flag on).
- `mangohud`, `vkBasalt`, `protontricks`, `lutris`, `wineWowPackages.full` included.
- `vm.max_map_count` raised to 2,147,483,642 matching Proton’s recommendation for large UE assets.
- Environment overrides:
  - `PROTON_ENABLE_NVAPI=1`, `DXVK_NVAPI_ALLOW_OTHER_DRIVERS=1` to unlock RTX-specific paths.
  - `PROTON_EAC_RUNTIME=1` + `WINE_FULLSCREEN_FSR=1` for anti-cheat runtime and upscaling.
  - `VKD3D_CONFIG=dxr11` enables DXR 1.1 in vkd3d for supporting titles.

## Recommended Workflow

1. **Steam Settings**
   - Enable “Force Proton-GE for title” from the compatibility dropdown.
   - Toggle “Enable shader pre-caching” globally.
   - Opt into Steam Play for all titles so non-whitelisted games pick Proton-GE automatically.

2. **Gamemode/Gamescope**
   - Launch heavy games via `gamemoderun gamescope -f -r 165 -W 1920 -H 1080 -- %command%`.
   - Use `MANGOHUD=1` (enabled by default) to track frame pacing; toggle with `Shift+F12`.

3. **Unreal Engine Games**
   - Keep FSR on (`WINE_FULLSCREEN_FSR=1`) and consider `PROTON_OLD_GL_STRING=1` for older UE4 titles if they mis-detect the GPU.
   - If stutter occurs, set `PROTON_NO_WRITE_WATCH=1` per-game (helps some UE shooters).

4. **Troubleshooting**
   - `protontricks <appid> --gui` to install dotnet/vcredist.
   - `vkBasalt` overlays can conflict with Easy Anti-Cheat; disable by setting `VK_INSTANCE_LAYERS=` per-game if needed.

These recommendations are based on Valve’s ProtonDB guidance, NVIDIA’s PRIME offload docs, and community notes for 40‑series laptops. Update Proton-GE regularly (`pkgs.steamPackages.proton-ge-bin`) to pick up UE-specific fixes.
