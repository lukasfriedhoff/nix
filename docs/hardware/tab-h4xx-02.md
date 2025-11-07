# tab-h4xx-02 (ASUS VivoBook T3300)

- **Form factor**: Detachable 13" tablet with Intel SoC and on-board eMMC storage.
- **Desktop**: GNOME on Wayland (good touch/pen support).
- **Input**: Touchscreen + pen via libinput/libwacom; accelerometer exposed through IIO.
- **Storage quirk**: The built-in eMMC freezes when command queueing is enabled. The module `modules/nixos/hardware/asus/vivobook-t3300.nix` disables blk-mq and limits the mmc queue depth via:
  - `boot.kernelParams = [ "mmc_core.queue_depth=2" "mmc_core.default_cmdq_depth=0" ];`
  - A `systemd` oneshot (`disable-emmc-cq`) that writes `0` to `/sys/block/mmcblk*/queue/use_cq`.

If you replace the storage or the kernel fixes this upstream, remove the workaround to regain multi-queue performance.

## Bring-up Checklist

1. Regenerate `hosts/tab-h4xx-02/hardware-configuration.nix` on the device (`nixos-generate-config`).
2. Ensure the `tab` secrets profile has the required SOPS files under `secrets/personal/tab-h4xx-02/`.
3. Deploy via `nixos-rebuild --flake .#tab-h4xx-02 switch`.
