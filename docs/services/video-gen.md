# AI video generation on work-mbp-01 (ComfyUI), consumed from tux

ComfyUI serves a Wan 2.x text-to-video web UI on demand (no login autostart).
The work Mac doubles as the local LLM machine (`docs/services/local-llm.md`):
both runtimes share 36 GB of unified memory, so run one at a time —
`llama-stop` before generating, `video-stop` when done.

| | ComfyUI (work-mbp-01) |
|---|---|
| Module | `lukasf.videoGen` (`modules/features/video-gen/home.nix`, mirrors `lukasf.llamaCppServer`) |
| Package | `comfyui` from the pinned `nixpkgs-unstable` input (not in stable nixpkgs for aarch64-darwin) |
| Port | 8188 |
| First model | Wan 2.2 TI2V-5B fp16 (official Comfy-Org repackage; FP8 weights do not work on MPS) |
| Start / stop / logs | `video-start` / `video-stop` / `video-logs` (Mac) |
| Pre-download | `video-pull [preset]` (Mac) |
| Tunnel to tux | `video-share-tux [host]` (Mac) |
| Open the UI | `video-open` (tux) |
| Wait for the tunnel | `video-wait` (tux) |
| Fetch a clip | `video-fetch <filename>` -> `~/media/Videos/ai/` (tux) |

## Mac side (implemented)

`lukasf.videoGen` (`modules/features/video-gen/home.nix`), applied to
`hosts/work/work-mbp-01`, structured like `llama-cpp-server/home.nix`:
a launchd user agent with `RunAtLoad`/`KeepAlive` off, driven by the
`video-*` aliases, plus a `video-pull` that fetches preset weights with
the standalone `hf` CLI and symlinks them into the models tree. `comfyui`
comes from the same pinned `nixpkgs-unstable` input as the llama.cpp
override (both need fresh PyTorch/Metal for M5 Max; the stable nixpkgs
26.05 has no `comfyui` for aarch64-darwin, so the host pins the input).
The models base dir is `~/.local/share/comfyui` (the package default
under HM's XDG would be `~/Library/Application Support/comfyui`).

Model presets for `video-pull` (Hugging Face, into the ComfyUI user
models dir), picked 2026-11 against the ~28 GB Metal budget:

| Preset | Model | Weights | Why kept or dropped |
|---|---|---|---|
| `wan2.2:5b` | Wan 2.2 TI2V-5B (Alibaba, Apache 2.0) | ~22.8 GB: FP16 transformer (10.0 GB) + umt5-xxl encoder (11.4 GB) + VAE (1.4 GB), all `Comfy-Org/Wan-2.2` | first preset: best-documented Mac path, text-to-video and image-to-video, ~12 min for 832x480 @ 101 frames on an M5 Max |
| `ltx2.3` (optional, no preset yet) | LTX-2.3 (Lightricks, 22B) | 14.2 GB Q4_K_M GGUF transformer (`unsloth/LTX-2.3-GGUF`); official fp8 weights are 46 GB | faster, generates audio too; LTX-2.x Community License (free under $10 M revenue). No `video-pull` preset yet: GGUF loading needs the `ComfyUI-GGUF` custom node plus an LTX text encoder and VAE pulled separately — add as a follow-up |
| — | Wan 2.2 T2V-A14B | ~26 GB at Q4 (high+low noise experts) | dropped: plus the text encoder that exceeds the ~28 GB Metal budget |

Generation times are minutes per clip, not seconds — expect roughly
12-35 min for a 5-second clip depending on model and resolution.

## Sampler: use `euler`, never `uni_pc` (MPS)

The stock ComfyUI "Wan 2.2 5B Video Generation" template defaults to
`uni_pc` / `simple`, shift 8, 20 steps, cfg 5. On MPS that silently
produces a green, blown-out smear with no scene in it —
[Comfy-Org/ComfyUI#16573](https://github.com/Comfy-Org/ComfyUI/issues/16573):
`uni_pc` computes its phi-coefficient recurrence in float32 on-device, and
MPS's imprecise `torch.expm1` makes one coefficient come out 55.39 instead
of 0.2496. Latent correlation against a correct reference is 0.15. The fix
(PR #16574) is unmerged as of ComfyUI 0.37.0 / PyTorch 2.13.0.

Switch the KSampler's `sampler_name` to `euler` and leave everything else
alone. Measured on work-mbp-01 2026-11-12, same prompt and seed:

| | `uni_pc`, 1280x704 @ 121f | `euler`, 832x480 @ 49f | `euler`, 832x480 @ 121f |
|---|---|---|---|
| Output | unusable | photoreal | photoreal, clean to frame 121 |
| Clip length | 5.0 s | 2.0 s | 5.0 s |
| Wall clock | 53 min (140 s/it) | 3.7 min (5.6 s/it) | 12 min (23.8 s/it) |

`length` must be 4n+1; 121 @ 24 fps is the model's trained clip length.

Part of that speedup is the smaller latent, but not most of it: the first
run was swap-bound (9.9 of 11.3 GB swap in use) while the weights were
still settling. Prefer 832x480 — large attention matrices are also what
[#15010](https://github.com/Comfy-Org/ComfyUI/issues/15010) and the related
MPS corruption reports implicate.

## tux side (implemented)

`tux` profile aliases (`modules/features/profile/desktop/home.nix`,
gated on `profile == "tux"`):

```bash
video-wait                     # block until the tunnel carries the UI
video-open                     # open the ComfyUI web UI
video-fetch 00001_ab12.mp4     # pull a generated clip into ~/media/Videos/ai/
```

No sshd change was needed: the Mac reuses the `tux` work-ssh alias and the
`tunnel-tux` key, which `users.users.lukasf.openssh.authorizedKeys.keyFiles`
already renders into `/etc/ssh/authorized_keys.d/lukasf`. tux's
`ClientAliveInterval`/`CountMax` reap dead tunnel sessions within a minute,
so a reconnect frees port 8188 for the next `video-share-tux`.

Flow:

```bash
# Mac
video-start
video-share-tux [host]         # foreground retry loop, ctrl+c to end
# tux
video-wait
video-open
video-fetch <filename>         # filename visible on the UI's output
```

mDNS only resolves on the same LAN; pass tux's current address (on tux:
`ip -4 -br addr`) otherwise, exactly like the llama tunnel.
