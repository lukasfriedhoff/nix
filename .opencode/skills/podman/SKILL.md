---
name: podman
description: Podman containers and Quadlet systemd integration
globs:
  - "**/*.container"
  - "**/containers/**"
  - "**/podman/**"
---

# Podman Skill

Container management with Podman and Quadlet systemd integration.

## Quadlet Container Files

Location: `/etc/containers/systemd/` or `~/.config/containers/systemd/`

```ini
[Unit]
Description=My Container
After=network-online.target

[Container]
ContainerName=myapp
Image=docker.io/library/nginx:latest
PublishPort=8080:80
Volume=/data:/app/data:Z
Environment=KEY=value
AddDevice=/dev/dri

[Service]
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

## GPU Passthrough (AMD ROCm)

```ini
AddDevice=/dev/kfd
AddDevice=/dev/dri
Environment=HSA_OVERRIDE_GFX_VERSION=11.0.0
```

## Commands

```bash
podman ps -a                    # List containers
podman logs <name>              # View logs
podman exec -it <name> bash     # Shell into container
podman inspect <name>           # Container details
systemctl --user daemon-reload  # Reload quadlet files
```

## Networking

```ini
Network=host                    # Host networking
Network=podman                  # Default bridge
AddHost=hostname:ip             # Custom hosts entry
```

## Best Practices

- Use `:Z` or `:z` for SELinux volume labels
- Set `SecurityLabelDisable=true` if SELinux causes issues
- Use `Pull=newer` for auto-updates
