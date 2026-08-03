#!/usr/bin/env bash
# Configure an experimental AirLLM OpenAI-compatible API on srv4.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: AIRLLM_MODEL_ID=<hf-model> scripts/servers/setup-srv4-airllm-runtime.sh [ssh-host] [install-root] [owner-user]

Examples:
  AIRLLM_MODEL_ID=meta-llama/Llama-2-7b-chat-hf scripts/servers/setup-srv4-airllm-runtime.sh

Environment overrides:
  AIRLLM_MODEL_ID        Hugging Face/safetensors model id to load with AirLLM
  AIRLLM_SERVICE_NAME    systemd service name
                         default: airllm-openai
  AIRLLM_HOST            API bind host
                         default: 127.0.0.1
  AIRLLM_PORT            API port
                         default: 11435
  AIRLLM_MAX_NEW_TOKENS  default generation token budget
                         default: 512
  AIRLLM_TRUST_REMOTE_CODE
                         allow Hugging Face model repositories to execute code
                         default: 0
  AIRLLM_ALLOW_UNAUTHENTICATED_REMOTE
                         required when AIRLLM_HOST is not loopback
                         default: 0
  AIRLLM_PACKAGE_SPEC    pinned AirLLM package requirement
                         default: airllm==3.1.0

Notes:
  - This is experimental. AirLLM is not llama.cpp and does not consume GGUF files.
  - The service exposes /health, /v1/models, and /v1/chat/completions.
  - Requires SSH access and passwordless sudo on the target host.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

host="${1:-srv4}"
remote_user="${3:-}"
service_name="${AIRLLM_SERVICE_NAME:-airllm-openai}"
airllm_model_id="${AIRLLM_MODEL_ID:-}"
airllm_host="${AIRLLM_HOST:-127.0.0.1}"
airllm_port="${AIRLLM_PORT:-11435}"
airllm_max_new_tokens="${AIRLLM_MAX_NEW_TOKENS:-512}"
airllm_trust_remote_code="${AIRLLM_TRUST_REMOTE_CODE:-0}"
airllm_allow_unauthenticated_remote="${AIRLLM_ALLOW_UNAUTHENTICATED_REMOTE:-0}"
airllm_package_spec="${AIRLLM_PACKAGE_SPEC:-airllm==3.1.0}"

if [[ -z "${airllm_model_id}" ]]; then
  echo "error: AIRLLM_MODEL_ID is required" >&2
  exit 2
fi
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
if [[ ! "${service_name}" =~ ^[a-zA-Z0-9_.@-]+$ ]]; then
  echo "error: invalid AIRLLM_SERVICE_NAME '${service_name}'" >&2
  exit 2
fi
for boolean_setting in \
  "AIRLLM_TRUST_REMOTE_CODE=${airllm_trust_remote_code}" \
  "AIRLLM_ALLOW_UNAUTHENTICATED_REMOTE=${airllm_allow_unauthenticated_remote}"; do
  boolean_value="${boolean_setting#*=}"
  if [[ "${boolean_value}" != "0" && "${boolean_value}" != "1" ]]; then
    echo "error: ${boolean_setting%%=*} must be 0 or 1" >&2
    exit 2
  fi
done
if [[ "${airllm_host}" != "127.0.0.1" && "${airllm_host}" != "::1" && "${airllm_allow_unauthenticated_remote}" != "1" ]]; then
  echo "error: refusing unauthenticated non-loopback bind; set AIRLLM_ALLOW_UNAUTHENTICATED_REMOTE=1 explicitly" >&2
  exit 2
fi
for numeric_setting in \
  "AIRLLM_PORT=${airllm_port}" \
  "AIRLLM_MAX_NEW_TOKENS=${airllm_max_new_tokens}"; do
  numeric_value="${numeric_setting#*=}"
  if [[ ! "${numeric_value}" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: ${numeric_setting%%=*} must be a positive integer" >&2
    exit 2
  fi
done

install_root="${2:-/home/${remote_user}/container-data/airllm}"
for shell_setting in \
  "AIRLLM_MODEL_ID=${airllm_model_id}" \
  "AIRLLM_HOST=${airllm_host}" \
  "AIRLLM_PACKAGE_SPEC=${airllm_package_spec}" \
  "INSTALL_ROOT=${install_root}"; do
  shell_value="${shell_setting#*=}"
  if [[ "${shell_value}" == *"'"* || "${shell_value}" == *$'\n'* || "${shell_value}" == *$'\r'* ]]; then
    echo "error: ${shell_setting%%=*} must not contain quotes or newlines" >&2
    exit 2
  fi
done

echo ">> Validating remote sudo on ${host}"
ssh "${host}" 'sudo -n true'

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

cat > "${tmp_dir}/airllm_openai.py" <<'PY'
import os
import time
import uuid
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

MODEL_ID = os.environ["AIRLLM_MODEL_ID"]
MAX_NEW_TOKENS = int(os.environ.get("AIRLLM_MAX_NEW_TOKENS", "512"))
TRUST_REMOTE_CODE = os.environ.get("AIRLLM_TRUST_REMOTE_CODE", "0") == "1"

app = FastAPI(title="srv4 AirLLM OpenAI shim")
model = None
tokenizer = None


class ChatMessage(BaseModel):
    role: str
    content: Any


class ChatCompletionRequest(BaseModel):
    model: str = Field(default=MODEL_ID)
    messages: list[ChatMessage]
    max_tokens: int | None = None
    temperature: float | None = None
    stream: bool = False


def load_model():
    global model, tokenizer
    if model is not None:
        return model, tokenizer
    from airllm import AutoModel
    from transformers import AutoTokenizer

    tokenizer = AutoTokenizer.from_pretrained(
        MODEL_ID,
        trust_remote_code=TRUST_REMOTE_CODE,
    )
    model = AutoModel.from_pretrained(
        MODEL_ID,
        trust_remote_code=TRUST_REMOTE_CODE,
    )
    return model, tokenizer


def render_prompt(messages: list[ChatMessage]) -> str:
    rendered: list[dict[str, Any]] = [
        {"role": message.role, "content": message.content} for message in messages
    ]
    if tokenizer is not None and hasattr(tokenizer, "apply_chat_template"):
        return tokenizer.apply_chat_template(
            rendered,
            tokenize=False,
            add_generation_prompt=True,
        )
    return "\n".join(f"{message.role}: {message.content}" for message in messages) + "\nassistant:"


@app.get("/health")
def health():
    return {"status": "ok", "model": MODEL_ID, "loaded": model is not None}


@app.get("/v1/models")
def models():
    return {
        "object": "list",
        "data": [{"id": MODEL_ID, "object": "model", "created": 0, "owned_by": "srv4-airllm"}],
    }


@app.post("/v1/chat/completions")
def chat_completions(request: ChatCompletionRequest):
    if request.stream:
        raise HTTPException(status_code=400, detail="streaming is not implemented")
    loaded_model, loaded_tokenizer = load_model()
    prompt = render_prompt(request.messages)
    input_ids = loaded_tokenizer(prompt, return_tensors="pt").input_ids
    output_ids = loaded_model.generate(
        input_ids,
        max_new_tokens=request.max_tokens or MAX_NEW_TOKENS,
        temperature=request.temperature if request.temperature is not None else 0.2,
    )
    content = loaded_tokenizer.decode(output_ids[0][input_ids.shape[-1] :], skip_special_tokens=True)
    now = int(time.time())
    return {
        "id": f"chatcmpl-{uuid.uuid4().hex}",
        "object": "chat.completion",
        "created": now,
        "model": request.model,
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": content},
                "finish_reason": "stop",
            }
        ],
        "usage": {
            "prompt_tokens": int(input_ids.shape[-1]),
            "completion_tokens": None,
            "total_tokens": None,
        },
    }
PY

cat > "${tmp_dir}/${service_name}.service" <<EOF
[Unit]
Description=srv4 experimental AirLLM OpenAI API
After=network-online.target
Wants=network-online.target

[Service]
User=${remote_user}
WorkingDirectory=${install_root}
Environment=AIRLLM_MODEL_ID=${airllm_model_id}
Environment=AIRLLM_MAX_NEW_TOKENS=${airllm_max_new_tokens}
Environment=AIRLLM_TRUST_REMOTE_CODE=${airllm_trust_remote_code}
Environment=HF_HOME=${install_root}/cache/huggingface
ExecStart=${install_root}/venv/bin/uvicorn airllm_openai:app --host ${airllm_host} --port ${airllm_port}
Restart=on-failure
RestartSec=5
TimeoutStartSec=1800

[Install]
WantedBy=multi-user.target
EOF

remote_app_tmp="/tmp/${service_name}.airllm_openai.py"
remote_unit_tmp="/tmp/${service_name}.service"

echo ">> Installing experimental AirLLM API on ${host}"
scp "${tmp_dir}/airllm_openai.py" "${host}:${remote_app_tmp}"
scp "${tmp_dir}/${service_name}.service" "${host}:${remote_unit_tmp}"
ssh "${host}" "set -euo pipefail
sudo install -d -m 0755 '${install_root}' '${install_root}/cache'
sudo chown -R '${remote_user}':'${remote_user}' '${install_root}'

if ! command -v python3 >/dev/null 2>&1; then
  echo 'error: python3 is required on srv4' >&2
  exit 1
fi
if [ ! -x '${install_root}/venv/bin/python' ]; then
  python3 -m venv '${install_root}/venv'
fi
'${install_root}/venv/bin/python' -m pip install 'fastapi>=0.115,<1' 'uvicorn[standard]>=0.30,<1' '${airllm_package_spec}'
sudo install -o '${remote_user}' -g '${remote_user}' -m 0644 '${remote_app_tmp}' '${install_root}/airllm_openai.py'
sudo install -m 0644 '${remote_unit_tmp}' '/etc/systemd/system/${service_name}.service'
rm -f '${remote_app_tmp}' '${remote_unit_tmp}'
sudo systemctl daemon-reload
sudo systemctl enable --now '${service_name}.service'
"

echo ">> Waiting for AirLLM API"
ssh "${host}" "set -euo pipefail
for _ in \$(seq 1 90); do
  curl -fsS 'http://127.0.0.1:${airllm_port}/health' >/dev/null 2>&1 && break
  sleep 2
done
curl -fsS 'http://127.0.0.1:${airllm_port}/health'; echo
sudo systemctl --no-pager --full status '${service_name}.service' | sed -n '1,80p'
"
