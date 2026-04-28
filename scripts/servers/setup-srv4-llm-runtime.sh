#!/usr/bin/env bash
# Configure ollama + open-webui on srv4 (RHEL) via systemd quadlet units.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/servers/setup-srv4-llm-runtime.sh [ssh-host] [data-root] [owner-user]

Examples:
  scripts/servers/setup-srv4-llm-runtime.sh
  scripts/servers/setup-srv4-llm-runtime.sh srv4 /home/lukasf/container-data
  scripts/servers/setup-srv4-llm-runtime.sh srv4 /home/media/container-data media

Notes:
  - Requires SSH access and passwordless sudo on the target host.
  - Creates/updates:
      /etc/containers/systemd/ollama-podman.container
      /etc/containers/systemd/open-webui-podman.container
  - Restarts:
      ollama-podman.service
      open-webui-podman.service
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

host="${1:-srv4}"
remote_user="${3:-}"

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

data_root="${2:-/home/${remote_user}/container-data}"
ollama_data="${data_root}/ollama"
openwebui_data="${data_root}/open-webui"

echo ">> Validating remote sudo on ${host}"
ssh "${host}" 'sudo -n true'

echo ">> Configuring LLM runtime on ${host}"
ssh "${host}" "set -euo pipefail
sudo systemctl disable --now ollama.service >/dev/null 2>&1 || true
sudo systemctl stop open-webui-podman.service ollama-podman.service >/dev/null 2>&1 || true
sudo podman rm -f open-webui >/dev/null 2>&1 || true
sudo install -d -m 0755 '${ollama_data}' '${openwebui_data}'
sudo chown -R '${remote_user}':'${remote_user}' '${data_root}'

if [ -d /var/lib/ollama ] && [ -z \"\$(ls -A '${ollama_data}' 2>/dev/null)\" ]; then
  sudo rsync -a /var/lib/ollama/ '${ollama_data}'/
fi
if [ -d /var/lib/open-webui ] && [ -z \"\$(ls -A '${openwebui_data}' 2>/dev/null)\" ]; then
  sudo rsync -a /var/lib/open-webui/ '${openwebui_data}'/
fi

cat <<'EOF' | sudo tee /etc/containers/systemd/ollama-podman.container >/dev/null
[Unit]
Description=Ollama LLM runtime (podman)
After=network-online.target
Wants=network-online.target

[Service]
Restart=on-failure
RestartSec=5
TimeoutStartSec=900

[Container]
ContainerName=ollama
Image=docker.io/ollama/ollama:latest
Pull=newer
PublishPort=11434:11434
Volume=${ollama_data}:/root/.ollama:Z
Environment=OLLAMA_HOST=0.0.0.0:11434
AddDevice=/dev/kfd
AddDevice=/dev/dri
SecurityLabelDisable=true
PodmanArgs=--ipc=host

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' | sudo tee /etc/containers/systemd/open-webui-podman.container >/dev/null
[Unit]
Description=Open WebUI frontend (podman)
After=network-online.target ollama-podman.service
Wants=network-online.target ollama-podman.service

[Service]
Restart=on-failure
RestartSec=5
TimeoutStartSec=900

[Container]
ContainerName=open-webui
Image=ghcr.io/open-webui/open-webui:main
Pull=newer
PublishPort=3000:8080
Volume=${openwebui_data}:/app/backend/data:Z
Environment=OLLAMA_BASE_URL=http://host.containers.internal:11434
Environment=WEBUI_AUTH=True

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl restart ollama-podman.service open-webui-podman.service
"

echo ">> Waiting for APIs"
ssh "${host}" "set -euo pipefail
for _ in \$(seq 1 60); do
  curl -fsS 'http://127.0.0.1:11434/api/version' >/dev/null 2>&1 && break
  sleep 2
done
for _ in \$(seq 1 90); do
  curl -fsS 'http://127.0.0.1:3000/api/version' >/dev/null 2>&1 && break
  sleep 2
done
curl -fsS 'http://127.0.0.1:11434/api/version'; echo
curl -fsS 'http://127.0.0.1:3000/api/version'; echo
sudo systemctl --no-pager --full status ollama-podman.service open-webui-podman.service | sed -n '1,80p'
"

echo ">> Done. Data roots:"
echo "   - ${ollama_data}"
echo "   - ${openwebui_data}"
