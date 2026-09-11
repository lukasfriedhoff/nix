# Local LLM server on work-mbp-01

llama.cpp serves an OpenAI-compatible API on demand (no login autostart).
Model weights download from Hugging Face into `~/.cache/huggingface`.

| | llama.cpp |
|---|---|
| Module | `lukasf.llamaCppServer` |
| Port | 11434 |
| Format | GGUF (router mode, preset INI) |
| Start / stop / logs | `llama-start` / `llama-stop` / `llama-logs` |
| Pre-download | `llama-pull [preset]` |
| opencode provider | `llama-cpp` |

The server is a launchd agent with `RunAtLoad`/`KeepAlive` off; the aliases
drive `launchctl kickstart` / `launchctl kill`. A loaded model claims GPU
memory until the server stops.

MLX was tried and dropped: the nixpkgs build has no Metal backend (CPU
only), and Apple's Metal wheels have no memory guard - a 27B under a real
opencode prompt exhausted unified memory and panicked the kernel. llama.cpp
(`fit=on`) refuses what does not fit and is the only runtime kept.

## Pull first, then start

llama-server can download presets on first use, but its in-process
downloader hangs when the CDN drops a connection mid-transfer (common on
multi-GB pulls). Pre-fetch with the standalone Hugging Face CLI instead,
which resumes and uses the `hf-token` secret (anonymous downloads are
throttled per IP):

```bash
llama-pull                 # default preset (qwen3.8:27b)
llama-pull qwen3-coder:30b # any preset name from the module
```

Progress: `du -sh ~/.cache/huggingface/hub/models--<org>--<repo>`; a pull
is complete when `blobs/` holds no `*.incomplete` files. If a pull stalls
(size stops growing for minutes), ctrl+c and re-run it - it resumes.

## llama.cpp presets

Router mode: `/v1/models` lists the presets from
`modules/features/llama-cpp-server/home.nix` (qwen3.8:27b, qwen3-coder:30b,
qwen3:8b - all 64k context); the model for a request is loaded on first use,
`--models-max 1` keeps a single model resident.

## opencode

Model entries declare `limit.context` matching the server window so opencode
compacts before hitting it (otherwise requests grow until the server
rejects them and compaction loops). Select models with `/models`.

## Sharing the Mac's server with tux

The Mac serves; tux consumes through a reverse SSH tunnel the Mac initiates:

```bash
llama-start                     # load the model locally
llama-share-tux                 # tunnel to tux-h4xx-01.local (mDNS default)
llama-share-tux 192.168.1.23    # or pass tux's current address explicitly
```

The function runs in the foreground; ctrl+c drops the tunnel. tux has no
stable address, so the argument overrides the SSH `Hostname` while the
`tux` work alias keeps supplying user and the dedicated tunnel key
(`~/.ssh/work/tunnel-tux`, authorized on tux via sshd AuthorizedKeysFile).

On tux, opencode then offers `llama-tunnel/...` ("llama.cpp via work-mbp-01")
at `localhost:11434`.
