# Docker on macOS (Colima)

`work-mbp-01` runs Docker headless through [Colima](https://github.com/abiosoft/colima)
(a Lima VM with the Docker daemon), configured by
`modules/features/devops/docker-headless/home.nix` via `programs.dockerHeadless`.

Autostart is disabled (`programs.dockerHeadless.startAtLogin = false`); the VM
is started on demand.

## Daily use

Shell aliases (defined by the module; work in any login shell):

| Command | Effect |
|---|---|
| `docker-start` | boot the Colima VM (first start creates it: 4 CPU / 8 GiB / 100 GiB) |
| `docker-stop` | shut the VM down and free its memory |
| `docker-status` | VM state and socket paths |
| `docker-logs` | tail the agent log (`~/.local/state/colima/default.log`) |

The raw equivalents are `colima start` / `colima stop` / `colima status`
(`COLIMA_HOME` points at `~/.config/colima` via session variables).
`docker` talks to the VM through `DOCKER_HOST`, also set as a session variable.

## Troubleshooting

- **`colima is not running` right after a reboot / crash**: stale Lima
  hostagent files can block startup. Remove them and start again:

  ```bash
  rm -f ~/.config/colima/_lima/colima/{ha.pid,ha.sock,ssh.sock,vz.pid}
  docker-start
  ```

- **`docker` cannot connect but the VM runs**: the shell is missing the
  session variables (`DOCKER_HOST`, `DOCKER_CONFIG`) - open a new login
  shell, or `source /etc/profiles/per-user/$USER/etc/profile.d/hm-session-vars.sh`.

- Re-enable autostart by removing `startAtLogin = false` from the host
  config (the module default starts the VM via a launchd agent at login).
