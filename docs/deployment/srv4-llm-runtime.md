# srv4 LLM Runtime (RHEL + systemd/podman)

This runbook keeps the LLM runtime on the existing RHEL `srv4` host using
systemd-managed podman containers:

- `ollama` on `:11434`
- `open-webui` on `:3000`

Data is persisted under `/home/<ssh-user>/container-data/` (not `/var/lib`).

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

1. Stops legacy native `ollama.service` and stale `open-webui` container.
2. Writes quadlet definitions to `/etc/containers/systemd/`.
3. Restarts `ollama-podman.service` and `open-webui-podman.service`.
4. Waits for both APIs to become healthy.

## Verify runtime

```bash
ssh srv4 'curl -fsS http://127.0.0.1:11434/api/version'
ssh srv4 'curl -fsS http://127.0.0.1:3000/api/version'
ssh srv4 'sudo systemctl status ollama-podman.service open-webui-podman.service --no-pager -l'
```

## Desktop integration

Home Manager desktop profile defaults are wired to this runtime:

- `OLLAMA_HOST=http://srv4.lab.h4xx.io:11434`
- `NVIM_OLLAMA_URL=http://srv4.lab.h4xx.io:11434`
- `OPENWEBUI_URL=http://srv4.lab.h4xx.io:3000`

For profile `srv4`, localhost endpoints are used instead.

## Notes

- First Open WebUI startup can take a while (DB migrations + model cache setup).
- Ollama currently reports CPU inference on this host. If GPU offload is needed,
  check ROCm/driver compatibility on `srv4`.
