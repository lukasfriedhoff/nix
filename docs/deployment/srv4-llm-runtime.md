# srv4 LLM Runtime (RHEL + systemd/podman)

This runbook keeps the LLM runtime on the existing RHEL `srv4` host using
systemd-managed podman containers:

- `llama.cpp` on `:11434` with the OpenAI-compatible API under `/v1`
- `open-webui` on `:3000`

Data is persisted under `/home/<ssh-user>/container-data/` (not `/var/lib`).
Old Ollama data is left in place but the Ollama service/quadlet is stopped and
disabled.

## One-command setup

From this repo:

```bash
scripts/servers/setup-srv4-llm-runtime.sh srv4 /home/lukasf/container-data
```

Defaults are already `srv4` + `/home/lukasf/container-data`, so this also works:

```bash
scripts/servers/setup-srv4-llm-runtime.sh
```

The script derives `<ssh-user>` from your SSH config for that host.
You can override the owner explicitly with a third argument:

```bash
scripts/servers/setup-srv4-llm-runtime.sh srv4 /home/media/container-data media
```

The script:

1. Stops legacy native `ollama.service`, `ollama-podman.service`, and stale containers.
2. Writes llama.cpp favorite model presets to `<data-root>/llama-cpp/models.ini`.
3. Writes quadlet definitions to `/etc/containers/systemd/`.
4. Restarts `llama-cpp-podman.service` and `open-webui-podman.service`.
5. Waits for both APIs to become healthy.

Default favorite model aliases:

- `qwen3-coder:30b`
- `qwen3-coder:30b-quality`
- `qwen3:8b`
- `qwen3:30b`

The models are GGUF/Hugging Face presets for `llama-server`; they are downloaded
on first use into `<data-root>/llama-cpp/cache`.

The script defaults to `ghcr.io/ggml-org/llama.cpp:server` so the API can come up
without pulling a full GPU runtime image. For srv4's AMD GPU, prefer the ROCm
image once the pull is available locally:

```bash
LLAMA_CPP_IMAGE=ghcr.io/ggml-org/llama.cpp:server-rocm scripts/servers/setup-srv4-llm-runtime.sh
```

The setup script detects `server-rocm` and adds `/dev/kfd`, `/dev/dri`, and the
ROCm container seccomp option. It also enables GPU layer offload in
`models.ini`. Vulkan is useful as a lighter fallback when ROCm is unavailable:

```bash
LLAMA_CPP_IMAGE=ghcr.io/ggml-org/llama.cpp:server-vulkan scripts/servers/setup-srv4-llm-runtime.sh
```

The script pre-pulls missing images before restarting services. Quadlets still
use `Pull=missing` so reruns use cached images. Remove the local image or run
`podman pull` on `srv4` first when you intentionally want an image update.

## Optional local Kimi K3 preset

Kimi K3 is currently wired for OpenCode through the hosted Kimi API. The local
srv4 llama.cpp path needs an official or trusted GGUF release first. When that
exists, add it to srv4 without changing OpenCode by passing both repo and file:

```bash
KIMI_K3_HF_REPO=owner/kimi-k3-gguf \
KIMI_K3_HF_FILE=kimi-k3-q4_k_m.gguf \
scripts/servers/setup-srv4-llm-runtime.sh
```

This adds a `kimi-k3` preset to `<data-root>/llama-cpp/models.ini`. Do not use
random third-party Kimi-named repos for this; wait for official weights or a
trusted conversion.

## AirLLM experiment

AirLLM is not a GGUF/llama.cpp runtime. It is only useful here if we expose a
separate OpenAI-compatible AirLLM service on srv4, currently reserved as:

- `http://127.0.0.1:11435/v1`
- OpenCode provider `airllm-srv4`

Use this only after selecting a Hugging Face/safetensors model that AirLLM
supports. Kimi K3 cannot be tested locally through AirLLM until compatible
weights are published.

The API binds to loopback because the shim has no application-level
authentication. From another workstation, open an SSH tunnel before using the
provider:

```bash
airllm-srv4-tunnel
```

Keep that command running in a separate terminal. It forwards local port
`11435` to srv4 without exposing the API on the LAN.

Provision the experimental service with:

```bash
AIRLLM_MODEL_ID=owner/model scripts/servers/setup-srv4-airllm-runtime.sh
```

The script creates a Python virtualenv under
`/home/<ssh-user>/container-data/airllm`, installs `airllm`, and starts
`airllm-openai.service`.

## Verify runtime

```bash
ssh srv4 'curl -fsS http://127.0.0.1:11434/health'
ssh srv4 'curl -fsS http://127.0.0.1:11434/v1/models'
ssh srv4 'curl -fsS http://127.0.0.1:3000/api/version'
ssh srv4 'sudo systemctl status llama-cpp-podman.service open-webui-podman.service --no-pager -l'
```

## Desktop integration

Home Manager desktop profile defaults are wired to this runtime:

- `LLAMA_CPP_BASE_URL=http://srv4.lab.h4xx.io:11434/v1`
- `NVIM_LLM_BASE_URL=http://srv4.lab.h4xx.io:11434/v1`
- `NVIM_LLM_MODEL=qwen3:8b`
- `OPENCODE_MODEL=llama-cpp/qwen3:8b`
- `OPENCODE_KIMI_API_MODEL=kimi-api/kimi-k3`
- `OPENCODE_AIRLLM_MODEL=airllm-srv4/kimi-k3`
- `OPENWEBUI_URL=http://srv4.lab.h4xx.io:3000`

For profile `srv4`, localhost endpoints are used instead.

## Notes

- First Open WebUI startup can take a while (DB migrations + model cache setup).
- First model use can take a while because llama.cpp downloads the selected GGUF.
- ROCm on Radeon RX 7900-class cards is the preferred GPU path for srv4, but it
  depends on the host kernel/KFD device and ROCm image compatibility.
- AirLLM is kept as an explicit srv4 experiment because it is a separate Python
  runtime, not a drop-in llama.cpp backend.
