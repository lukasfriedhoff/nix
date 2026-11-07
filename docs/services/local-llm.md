# Local LLM server on work-mbp-01

llama.cpp serves an OpenAI-compatible API on demand (no login autostart).
Model weights live in the Hugging Face hub cache (`~/.cache/huggingface/hub`),
shared between `llama-pull` and llama-server's own downloader.

| | llama.cpp |
|---|---|
| Module | `lukasf.llamaCppServer` |
| Package | `llama-cpp` from the pinned `nixpkgs-unstable` input (see below) |
| Port | 11434 |
| Format | GGUF (router mode, preset INI) |
| Start / stop / logs | `llama-start` / `llama-stop` / `llama-logs` |
| Pre-download | `llama-pull [preset]` |
| opencode provider | `llama-cpp` (default model `llama-cpp/qwen3.6:35b`) |

The server is a launchd agent with `RunAtLoad`/`KeepAlive` off; the aliases
drive `launchctl kickstart` / `launchctl kill`. A loaded model claims GPU
memory until the server stops.

MLX was tried and dropped: the nixpkgs build has no Metal backend (CPU
only), and Apple's Metal wheels have no memory guard - a 27B under a real
opencode prompt exhausted unified memory and panicked the kernel. llama.cpp
(`fit=on`) refuses what does not fit and is the only runtime kept.

## Why the unstable llama.cpp

The stable channel's llama.cpp (build 9190, May 2026) logs `tensor API is
not supported in this environment` on the M5 Max and leaves the Neural
Accelerators idle. The build from the flake's `nixpkgs-unstable` input
(0.6.0, build 11429) reports `has tensor = true`: prompt processing more than
doubles (Qwen3-Coder-30B-A3B Q4 1204 -> 2712 tok/s, Qwen3.8-27B 211 -> 558),
generation is unchanged because it is bandwidth-bound. The host config
therefore sets `lukasf.llamaCppServer.package` to the unstable package, the
same pattern as the mac-app-util pin in `flake.nix`.

## Models

Four models were kept out of eleven candidates (benchmark below). Presets in
`modules/features/llama-cpp-server/home.nix`, all with a 64k window,
`fit=on`, `jinja=on` and the vision projector disabled (`mmproj-auto=off`;
remove that key from `common` to get image input back at ~1 GB of memory).

| Preset | Model (Q4) | Size | Decode tok/s at 0 / 16k ctx | Role |
|---|---|---|---|---|
| `qwen3.6:35b` | Qwen3.6-35B-A3B, thinking off | 20.6 GiB | 92 / 81 | opencode default: fast agent turns (a small coding task in 3-11 s) |
| `qwen3.6:35b-think` | same file, thinking on | 20.6 GiB | 92 / 81 | hard problems; expect 7-12k reasoning tokens per answer |
| `qwen3.8:27b` | Qwen3.8-27B, reasoning effort medium, **vision on, 128k window, MTP speculative decoding** | 15.3 GiB + 1.3 GiB draft + 0.9 GiB projector | 30 with MTP (22 without) | strongest raw quality; image input; long documents |
| `gpt-oss:20b` | gpt-oss-20b MXFP4, reasoning medium | 11.3 GiB | 126 / 98 | quick answers, smallest footprint |
| `gemma4:26b` | Gemma 4 26B-A4B | 15.8 GiB | 88 / 68 | second opinion from another family |

`--models-max 1` keeps one model resident; selecting another preset swaps it
(a few seconds from the page cache).

`qwen3.8:27b` is the exception to the text-only rule: it keeps the vision
projector, runs a 128k window with a q8_0 KV cache (4 GiB instead of 8) and
drafts with the model's MTP head (`spec-type = draft-mtp`). Measured
2026-11-07 on this Mac at 128k: all 66 layers on the GPU, decode 22 -> 30
tok/s, draft acceptance about 0.6. The MTP file sits in a subfolder of the
Hugging Face repo, which llama-server cannot fetch by tag, so `llama-pull
qwen3.8:27b` downloads it and links it as
`~/.cache/llama.cpp/drafts/qwen3.8-27b-mtp.gguf`; without that link the
preset fails to load.

## Pull first, then start

llama-server can download presets on first use, but its in-process
downloader hangs when the CDN drops a connection mid-transfer (common on
multi-GB pulls). Pre-fetch with the standalone Hugging Face CLI instead,
which resumes and uses the `hf-token` secret (anonymous downloads are
throttled per IP):

```bash
llama-pull                 # default preset (qwen3.6:35b)
llama-pull gpt-oss:20b     # any preset name from the module
llama-pull qwen3.8:27b     # also fetches and links its MTP draft file
```

Progress: `du -sh ~/.cache/huggingface/hub/models--<org>--<repo>`; a pull
is complete when `blobs/` holds no `*.incomplete` files. If a pull stalls
(size stops growing for minutes), ctrl+c and re-run it - it resumes.

Note for ad-hoc shells: llama-server and the `hf` CLI derive the cache from
`XDG_CACHE_HOME`; a shell that sets it to `~/Library/Caches` downloads a
second copy there. The launchd agent and login shells use `~/.cache`.

## llama.cpp presets

Router mode: `/v1/models` lists the presets above (the router upper-cases
the part after the colon, so `qwen3.6:35b-think` shows as `qwen3.6:THINK`;
requests by the full preset name still route correctly) plus one raw entry
per cached GGUF; the model for a request is loaded on first use. Preset keys are llama-server flags without dashes
(`reasoning = off`, `reasoning-effort = medium`, `mmproj-auto = off`).

## opencode

Model entries declare `limit.context` matching the server window so opencode
compacts before hitting it (otherwise requests grow until the server
rejects them and compaction loops). `limit.output` caps `max_tokens`: the
thinking presets get 32k because an 8k cap truncated Qwen3.6 mid-thought.
Select models with `/models`; the same five entries exist on tux under the
`llama-tunnel` provider.

## Sharing the Mac's server with tux

The Mac serves; tux consumes through a reverse SSH tunnel the Mac initiates:

```bash
llama-start                     # load the server locally
llama-share-tux                 # tunnel to tux-h4xx-01.local (mDNS default)
llama-share-tux 192.168.1.23    # or pass tux's current address explicitly
```

The function runs in the foreground and retries until ctrl+c: tux is on
WiFi and drops off the LAN for seconds at a time ("No route to host"), and
an established tunnel reconnects when keepalives detect a dead link. tux's
sshd reaps the stale session within a minute (`ClientAliveInterval`), so
the remote port is free again for the reconnect. tux has no
stable address, so the argument overrides the SSH `Hostname` while the
`tux` work alias keeps supplying user and the dedicated tunnel key
(`~/.ssh/work/tunnel-tux`, trusted on tux through
`users.users.lukasf.openssh.authorizedKeys.keyFiles`, i.e.
`/etc/ssh/authorized_keys.d/lukasf`). A password prompt means tux's sshd
rejected the key: before 2026-11-07 the key sat behind an `AuthorizedKeysFile`
entry in /nix/store, which StrictModes ignores because the store directory is
group-writable.
mDNS only resolves when both machines sit on the same LAN; elsewhere pass
the address tux currently has (on tux: `ip -4 -br addr`).

On tux, opencode then offers `llama-tunnel/...` ("llama.cpp via work-mbp-01")
at `localhost:11434`.

## Benchmark, 2026-10-30

llama-bench on this Mac (llama.cpp 0.6.0, Metal, flash attention, Q4 quants;
`-p 2048 -n 128 -d 0,16384`), followed by a smoke test per model through
llama-server: a tool call (`read_file src/main.rs`) and a small coding task
checked against asserts. Candidates were the newest member of each model
family that fits ~28 GB at Q4 with a 64k window and has llama.cpp support;
GLM-5.3-Flash (320B), DeepSeek V4-Flash (284B), Qwen3-Coder-Next (80B),
gpt-oss-120b and Mistral Small 4 (119B) do not fit.

| Model | Size | Prefill tok/s 0 / 16k | Decode tok/s 0 / 16k | Code task |
|---|---|---|---|---|
| Qwen3.6-35B-A3B | 20.6 GiB | 2692 / 1807 | 92 / 81 | pass (think 85 s / 7.5k tok, no-think 3 s / 270 tok) |
| Qwen3.8-27B | 15.3 GiB | 558 / 458 | 23 / 20 | pass (83 s / 1.9k tok, medium effort) |
| gpt-oss-20b | 11.3 GiB | 2890 / 1790 | 126 / 98 | pass (8 s / 1.0k tok) |
| Gemma 4 26B-A4B | 15.8 GiB | 2790 / 1901 | 88 / 68 | pass (59 s / 4.8k tok) |
| GLM-4.7-Flash | 16.3 GiB | 2052 / 460 | 89 / 36 | pass (113 s / 6.2k tok) |
| Nemotron 3.5 Lightning 30B-A3B | 19.8 GiB | 2512 / 2034 | 96 / 89 | pass (70 s / 6.5k tok) |
| LFM2.5-24B-A2B | 13.5 GiB | 3778 / 2806 | 167 / 139 | pass (28-64 s / 4-9k tok) |
| Muse Glimmer-30B | 15.6 GiB | 615 / 519 | 25 / 23 | pass (138 s / 3.2k tok) |
| Gemma 4 31B | 17.5 GiB | 509 / 376 | 20 / 17 | pass (123 s / 2.3k tok) |
| Devstral Small 2 24B | 13.3 GiB | 723 / 481 | 28 / 23 | pass (17 s / 424 tok) |
| Qwen3-Coder-30B-A3B (old default) | 17.3 GiB | 2712 / 877 | 132 / 65 | pass (2 s / 277 tok) |

Dropped: GLM-4.7-Flash uses conventional attention, so its KV cache grows
fast and it loses most of its speed once context builds up; the dense 27-31B
models all sit at 20-28 tok/s and none beats Qwen3.8-27B on quality; LFM2.5
is fastest but has the weakest vendor coding scores; Qwen3-Coder-30B-A3B is
superseded by Qwen3.6 in non-thinking mode; Nemotron adds nothing over
Qwen3.6 here.
