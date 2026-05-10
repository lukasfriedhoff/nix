---
name: systemd
description: Systemd services, timers, and unit patterns
globs:
  - "**/*.service"
  - "**/*.timer"
  - "**/systemd/**"
---

# Systemd Skill

Service management with systemd in NixOS.

## NixOS Service Definition

```nix
systemd.services.myservice = {
  description = "My Service";
  wantedBy = [ "multi-user.target" ];
  after = [ "network.target" ];
  serviceConfig = {
    Type = "simple";
    ExecStart = "${pkgs.myapp}/bin/myapp";
    Restart = "on-failure";
    User = "myuser";
    Group = "mygroup";
  };
  environment = {
    HOME = "/var/lib/myservice";
  };
};
```

## User Services

```nix
systemd.user.services.myservice = {
  # Same structure, runs as user
};
```

## Timers

```nix
systemd.timers.mytimer = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "daily";
    Persistent = true;
  };
};
```

## Commands

```bash
systemctl status <service>
systemctl restart <service>
journalctl -u <service> -f
systemctl daemon-reload
systemctl --user <command>      # User services
```

## Service Types

- `simple` - Main process is the service
- `oneshot` - Run once and exit
- `forking` - Forks a child process
- `notify` - Signals readiness via sd_notify
