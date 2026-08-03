#!/usr/bin/env bash
# Configure llama.cpp + open-webui on srv4 (RHEL) via systemd quadlet units.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/servers/setup-srv4-llm-runtime.sh [ssh-host] [data-root] [owner-user]

Examples:
  scripts/servers/setup-srv4-llm-runtime.sh
  scripts/servers/setup-srv4-llm-runtime.sh srv4 /home/lukasf/container-data
  scripts/servers/setup-srv4-llm-runtime.sh srv4 /home/media/container-data media

Environment overrides:
  LLAMA_CPP_IMAGE     llama.cpp container image
                      default: ghcr.io/ggml-org/llama.cpp:server
  LLAMA_CPP_GPU_BACKEND
                      auto, cpu, vulkan, or rocm
                      default: auto, inferred from LLAMA_CPP_IMAGE
  LLAMA_CPP_HSA_OVERRIDE_GFX_VERSION
                      optional ROCm workaround, for example 11.0.0
  LLAMA_CPP_MODELS_MAX
                      maximum concurrently loaded llama.cpp models
                      default: 2
  LLAMA_CPP_CACHE_RAM llama.cpp router RAM cache in MiB
                      default: 8192
  LLAMA_CPP_PARALLEL  llama.cpp parallel request slots
                      default: 2
  KIMI_K3_HF_REPO     optional Hugging Face repo for a local Kimi K3 GGUF preset
  KIMI_K3_HF_FILE     optional GGUF file inside KIMI_K3_HF_REPO
  KIMI_K3_ALIAS       optional local model aliases
                      default: kimi-k3,kimi
  KIMI_K3_CONTEXT     optional local Kimi K3 context size
                      default: 32768
  OPENWEBUI_IMAGE     Open WebUI container image
                      default: ghcr.io/open-webui/open-webui:main

Notes:
  - Requires SSH access and passwordless sudo on the target host.
  - Stops/disables old Ollama services, but does not delete Ollama data.
  - Creates/updates:
      /etc/containers/systemd/llama-cpp-podman.container
      /etc/containers/systemd/open-webui-podman.container
      <data-root>/llama-cpp/models.ini
  - Pre-pulls missing container images before restarting services.
  - Restarts:
      llama-cpp-podman.service
      open-webui-podman.service
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

host="${1:-srv4}"
remote_user="${3:-}"
llamacpp_image="${LLAMA_CPP_IMAGE:-ghcr.io/ggml-org/llama.cpp:server}"
llamacpp_gpu_backend="${LLAMA_CPP_GPU_BACKEND:-auto}"
llamacpp_models_max="${LLAMA_CPP_MODELS_MAX:-2}"
llamacpp_cache_ram="${LLAMA_CPP_CACHE_RAM:-8192}"
llamacpp_parallel="${LLAMA_CPP_PARALLEL:-2}"
openwebui_image="${OPENWEBUI_IMAGE:-ghcr.io/open-webui/open-webui:main}"
kimi_k3_hf_repo="${KIMI_K3_HF_REPO:-}"
kimi_k3_hf_file="${KIMI_K3_HF_FILE:-}"
kimi_k3_alias="${KIMI_K3_ALIAS:-kimi-k3,kimi}"
kimi_k3_context="${KIMI_K3_CONTEXT:-32768}"

if [[ -z "${remote_user}" ]]; then
  remote_user="$(ssh -G "${host}" | awk '$1 == "user" { print $2; exit }')"
fi
if [[ -z "${remote_user}" ]]; then
  remote_user="${USER}"
fi
if [[ ! "${remote_user}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "error: invalid remote user '${remote_user}'" >&2
  exit 2
fi
for numeric_setting in \
  "LLAMA_CPP_MODELS_MAX=${llamacpp_models_max}" \
  "LLAMA_CPP_CACHE_RAM=${llamacpp_cache_ram}" \
  "LLAMA_CPP_PARALLEL=${llamacpp_parallel}" \
  "KIMI_K3_CONTEXT=${kimi_k3_context}"; do
  numeric_value="${numeric_setting#*=}"
  if [[ ! "${numeric_value}" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: ${numeric_setting%%=*} must be a positive integer" >&2
    exit 2
  fi
done
if [[ -n "${kimi_k3_hf_repo}" || -n "${kimi_k3_hf_file}" ]]; then
  if [[ -z "${kimi_k3_hf_repo}" || -z "${kimi_k3_hf_file}" ]]; then
    echo "error: set both KIMI_K3_HF_REPO and KIMI_K3_HF_FILE for the local Kimi preset" >&2
    exit 2
  fi
  for kimi_setting in \
    "KIMI_K3_HF_REPO=${kimi_k3_hf_repo}" \
    "KIMI_K3_HF_FILE=${kimi_k3_hf_file}" \
    "KIMI_K3_ALIAS=${kimi_k3_alias}"; do
    kimi_value="${kimi_setting#*=}"
    if [[ "${kimi_value}" == *$'\n'* || "${kimi_value}" == *$'\r'* ]]; then
      echo "error: ${kimi_setting%%=*} must not contain newlines" >&2
      exit 2
    fi
  done
fi

data_root="${2:-/home/${remote_user}/container-data}"
llamacpp_data="${data_root}/llama-cpp"
llamacpp_cache="${llamacpp_data}/cache"
llamacpp_models="${llamacpp_data}/models"
llamacpp_preset="${llamacpp_data}/models.ini"
openwebui_data="${data_root}/open-webui"

for shell_setting in \
  "DATA_ROOT=${data_root}" \
  "LLAMA_CPP_IMAGE=${llamacpp_image}" \
  "OPENWEBUI_IMAGE=${openwebui_image}" \
  "KIMI_K3_HF_REPO=${kimi_k3_hf_repo}" \
  "KIMI_K3_HF_FILE=${kimi_k3_hf_file}" \
  "KIMI_K3_ALIAS=${kimi_k3_alias}" \
  "LLAMA_CPP_HSA_OVERRIDE_GFX_VERSION=${LLAMA_CPP_HSA_OVERRIDE_GFX_VERSION:-}"; do
  shell_value="${shell_setting#*=}"
  if [[ "${shell_value}" == *"'"* || "${shell_value}" == *$'\n'* || "${shell_value}" == *$'\r'* ]]; then
    echo "error: ${shell_setting%%=*} must not contain quotes or newlines" >&2
    exit 2
  fi
done

case "${llamacpp_gpu_backend}" in
  auto)
    case "${llamacpp_image}" in
      *rocm*) llamacpp_gpu_backend="rocm" ;;
      *vulkan*) llamacpp_gpu_backend="vulkan" ;;
      *) llamacpp_gpu_backend="cpu" ;;
    esac
    ;;
  cpu | rocm | vulkan) ;;
  *)
    echo "error: invalid LLAMA_CPP_GPU_BACKEND '${llamacpp_gpu_backend}'" >&2
    exit 2
    ;;
esac

llamacpp_accel_quadlet=""
llamacpp_preset_defaults=""
llamacpp_podman_args="--ipc=host"
case "${llamacpp_gpu_backend}" in
  rocm)
    llamacpp_accel_quadlet="AddDevice=/dev/kfd
AddDevice=/dev/dri"
    if [[ -n "${LLAMA_CPP_HSA_OVERRIDE_GFX_VERSION:-}" ]]; then
      llamacpp_accel_quadlet="${llamacpp_accel_quadlet}
Environment=HSA_OVERRIDE_GFX_VERSION=${LLAMA_CPP_HSA_OVERRIDE_GFX_VERSION}"
    fi
    llamacpp_podman_args="--ipc=host --security-opt=seccomp=unconfined"
    llamacpp_preset_defaults="[*]
n-gpu-layers = 999
flash-attn = on
"
    ;;
  vulkan)
    llamacpp_accel_quadlet="AddDevice=/dev/dri"
    llamacpp_preset_defaults="[*]
n-gpu-layers = 999
flash-attn = on
"
    ;;
esac

kimi_k3_preset=""
if [[ -n "${kimi_k3_hf_repo}" && -n "${kimi_k3_hf_file}" ]]; then
  kimi_k3_preset="
[kimi-k3]
hf-repo = ${kimi_k3_hf_repo}
hf-file = ${kimi_k3_hf_file}
alias = ${kimi_k3_alias}
c = ${kimi_k3_context}
fit = on
jinja = on
temp = 0.2
top-p = 0.95
min-p = 0.01
"
fi

echo ">> Validating remote sudo on ${host}"
ssh "${host}" 'sudo -n true'

echo ">> Configuring llama.cpp runtime on ${host} (${llamacpp_gpu_backend}, ${llamacpp_image})"
ssh "${host}" "set -euo pipefail
sudo systemctl disable --now ollama.service ollama-podman.service >/dev/null 2>&1 || true
sudo systemctl stop open-webui-podman.service llama-cpp-podman.service >/dev/null 2>&1 || true
sudo podman rm -f open-webui llama-cpp ollama >/dev/null 2>&1 || true
sudo rm -f /etc/containers/systemd/ollama-podman.container

sudo install -d -m 0755 '${llamacpp_data}' '${llamacpp_cache}' '${llamacpp_models}' '${openwebui_data}'
sudo chown -R '${remote_user}':'${remote_user}' '${data_root}'

if [ -d /var/lib/open-webui ] && [ -z \"\$(ls -A '${openwebui_data}' 2>/dev/null)\" ]; then
  sudo rsync -a /var/lib/open-webui/ '${openwebui_data}'/
fi

cat <<'EOF' | sudo tee '${llamacpp_preset}' >/dev/null
${llamacpp_preset_defaults}
[qwen3-coder:30b]
hf-repo = unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF
hf-file = Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf
alias = qwen3-coder:30b,qwen3-coder
c = 32768
fit = on
jinja = on
temp = 0.2
top-p = 0.95
min-p = 0.01

[qwen3-coder:30b-quality]
hf-repo = unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF
hf-file = Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf
alias = qwen3-coder:30b-quality
c = 32768
fit = on
jinja = on
temp = 0.2
top-p = 0.95
min-p = 0.01

[qwen3:8b]
hf-repo = Qwen/Qwen3-8B-GGUF
hf-file = Qwen3-8B-Q4_K_M.gguf
alias = qwen3:8b,qwen3-fast
c = 32768
fit = on
jinja = on

[qwen3:30b]
hf-repo = Qwen/Qwen3-30B-A3B-GGUF
hf-file = Qwen3-30B-A3B-Q4_K_M.gguf
alias = qwen3:30b
c = 32768
fit = on
jinja = on
${kimi_k3_preset}
EOF

cat <<'EOF' | sudo tee /etc/containers/systemd/llama-cpp-podman.container >/dev/null
[Unit]
Description=llama.cpp LLM runtime (podman)
After=network-online.target
Wants=network-online.target

[Service]
Restart=on-failure
RestartSec=5
TimeoutStartSec=1800

[Container]
ContainerName=llama-cpp
Image=${llamacpp_image}
Pull=missing
PublishPort=11434:8080
Volume=${llamacpp_models}:/models:Z
Volume=${llamacpp_cache}:/cache:Z
Volume=${llamacpp_preset}:/etc/llama-cpp/models.ini:ro,Z
Environment=LLAMA_CACHE=/cache/llama.cpp
Environment=HF_HOME=/cache/huggingface
${llamacpp_accel_quadlet}
SecurityLabelDisable=true
PodmanArgs=${llamacpp_podman_args}
Exec=--host 0.0.0.0 --port 8080 --models-preset /etc/llama-cpp/models.ini --models-dir /models --models-max ${llamacpp_models_max} --cache-ram ${llamacpp_cache_ram} --parallel ${llamacpp_parallel} --cont-batching

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' | sudo tee /etc/containers/systemd/open-webui-podman.container >/dev/null
[Unit]
Description=Open WebUI frontend (podman)
After=network-online.target llama-cpp-podman.service
Wants=network-online.target llama-cpp-podman.service

[Service]
Restart=on-failure
RestartSec=5
TimeoutStartSec=900

[Container]
ContainerName=open-webui
Image=${openwebui_image}
Pull=missing
PublishPort=3000:8080
Volume=${openwebui_data}:/app/backend/data:Z
Environment=ENABLE_OLLAMA_API=False
Environment=ENABLE_OPENAI_API=True
Environment=OPENAI_API_BASE_URL=http://host.containers.internal:11434/v1
Environment=OPENAI_API_BASE_URLS=http://host.containers.internal:11434/v1
Environment=OPENAI_API_KEY=sk-no-key-required
Environment=OPENAI_API_KEYS=sk-no-key-required
Environment=DEFAULT_MODELS=qwen3:8b
Environment=WEBUI_AUTH=True

[Install]
WantedBy=multi-user.target
EOF

if ! sudo podman image exists '${llamacpp_image}'; then
  sudo podman pull '${llamacpp_image}'
fi
if ! sudo podman image exists '${openwebui_image}'; then
  sudo podman pull '${openwebui_image}'
fi

sudo systemctl daemon-reload
sudo systemctl restart llama-cpp-podman.service open-webui-podman.service
"

echo ">> Waiting for APIs"
ssh "${host}" "set -euo pipefail
for _ in \$(seq 1 90); do
  curl -fsS 'http://127.0.0.1:11434/health' >/dev/null 2>&1 && break
  sleep 2
done
for _ in \$(seq 1 90); do
  curl -fsS 'http://127.0.0.1:3000/api/version' >/dev/null 2>&1 && break
  sleep 2
done
echo 'llama.cpp health:'
curl -fsS 'http://127.0.0.1:11434/health'; echo
echo 'llama.cpp models:'
curl -fsS 'http://127.0.0.1:11434/v1/models'; echo
echo 'Open WebUI version:'
curl -fsS 'http://127.0.0.1:3000/api/version'; echo
sudo systemctl --no-pager --full status llama-cpp-podman.service open-webui-podman.service | sed -n '1,100p'
"

echo ">> Done. Data roots:"
echo "   - ${llamacpp_data}"
echo "   - ${openwebui_data}"
