# Local LLM servers on work-mbp-01

Two OpenAI-compatible servers, both **started on demand** (no login
autostart). Model weights download from Hugging Face on first use into
`~/.cache/huggingface`.

| | llama.cpp | MLX |
|---|---|---|
| Module | `lukasf.llamaCppServer` | `lukasf.mlxLm` |
| Port | 11434 | 11435 |
| Format | GGUF (router mode, preset INI) | MLX quantizations |
| Start | `llama-start` | `mlx-start` |
| Stop | `llama-stop` | `mlx-stop` |
| Logs | `llama-logs` | `mlx-logs` |
| opencode provider | `llama-cpp` | `mlx` |

Both servers are launchd agents with `RunAtLoad`/`KeepAlive` off; the
aliases drive `launchctl kickstart` / `launchctl kill`. Only start what you
need - each loaded model claims GPU memory until its server stops.

## Pull first, then start

Both servers can download models on first use, but their in-process
downloaders hang when the CDN drops a connection mid-transfer (common on
20 GB pulls). Pre-fetch with the standalone Hugging Face CLI instead,
which resumes and uses the `hf-token` secret:

```bash
llama-pull                 # default preset (qwen3.8:27b)
llama-pull qwen3-coder:30b # any preset name from the llama.cpp module
mlx-pull                   # the configured MLX model
mlx-pull mlx-community/<repo>
```

Progress: `du -sh ~/.cache/huggingface/hub/models--<org>--<repo>`; a pull
is complete when `blobs/` holds no `*.incomplete` files. If a pull stalls
(size stops growing for minutes), ctrl+c and re-run it - it resumes.

## llama.cpp

Router mode: `/v1/models` lists the presets from
`modules/features/llama-cpp-server/home.nix` (qwen3-coder:30b,
qwen3.8:27b, qwen3:8b - all 64k context); the model for a request is
loaded on first use, `--models-max 1` keeps a single model resident.

## MLX

The runtime comes from Apple's PyPI wheels in a uv venv
(`~/.local/share/mlx-lm/venv`, versions pinned in `lukasf.mlxLm.pypiVersions`,
installed during `darwin-rebuild switch` - needs network once). nixpkgs'
mlx is built without Metal and runs on the CPU, which is unusable for LLMs;
verify with `~/.local/share/mlx-lm/venv/bin/python -c 'import mlx.core as mx; print(mx.metal.is_available())'`.

`mlx_lm.server` serves one model chosen at startup
(`lukasf.mlxLm.model`, default the MLX 4-bit build of qwen3-coder:30b).
To serve a different model ad hoc:

```bash
mlx_lm.server --host 127.0.0.1 --port 11435 --model mlx-community/<repo>
```

## opencode

Model entries declare `limit.context` matching the server windows; opencode
compacts before hitting them (see the compaction-loop postmortem in the
git history of `hosts/work/work-mbp-01/configuration.nix`). Select models
with `/models` in opencode; the `mlx/...` entries require the MLX server
to be running.

## Sharing the Mac's MLX server with tux

tux (x86_64) cannot run MLX; instead the Mac serves and tux consumes it
through a reverse SSH tunnel the Mac initiates:

```bash
mlx-start        # load the MLX model locally
mlx-share-tux                 # tunnel to tux-h4xx-01.local (mDNS default)
mlx-share-tux 192.168.1.23    # or pass tux's current address explicitly
```

The function runs in the foreground; ctrl+c drops the tunnel. tux has no
stable address, so the argument overrides the SSH `Hostname` while the
`tux` work alias keeps supplying user and the dedicated tunnel key
(`~/.ssh/work/tunnel-tux`, authorized on tux via sshd AuthorizedKeysFile).

On tux, opencode then offers `mlx-tunnel/...` ("MLX via work-mbp-01") at
`localhost:11435`.
