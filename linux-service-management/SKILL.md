---
name: linux-service-management
description: Manage systemd services on Ubuntu/Debian servers. Start, stop, restart, reload, enable/disable on boot, view status and logs via journalctl. Covers all web server services (nginx, apache2, mysql, postgresql, php-fpm, redis, fail2ban, certbot, cron, msmtp) and Node.js product services. Includes crashed-service diagnosis workflow.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Service Management

## Use when

- Managing `systemd` services on a Linux server.
- Investigating why a service failed, restarted, or will not enable correctly.
- Performing controlled restarts or reloads after config changes.

## Do not use when

- The task is only log analysis; use `linux-log-management`.
- The task is broad symptom-driven triage across multiple subsystems; use `linux-troubleshooting`.

## Required inputs

- The service name and symptom.
- Whether the task is inspection, restart/reload, enablement, or diagnosis.
- Any expected dependencies or recent changes affecting the service.

## Workflow

1. Inspect service status and recent logs before taking action.
2. Apply the smallest restart, reload, or enablement change needed.
3. Follow the crashed-service workflow when a normal restart is insufficient.
4. Confirm the unit is healthy and serving traffic after the change.

## Quality standards

- Status and logs come before restart loops.
- Prefer reloads when safe and supported.
- Verification must include both unit state and real service behavior.

## Anti-patterns

- Repeatedly restarting a failed service without reading why it failed.
- Assuming `active (running)` means the application is actually healthy.
- Reloading config-dependent services without validating their config first.

## Outputs

- The service action or diagnosis.
- The status and log evidence used to justify it.
- Post-change verification for the live unit and dependent service path.

## References

- [`references/service-reference.md`](references/service-reference.md)
- [`references/timers-and-cron.md`](references/timers-and-cron.md)

**This skill is self-contained.** Every command below is a standard
Ubuntu/Debian tool. The `sk-*` scripts in the **Optional fast path** section
are convenience wrappers — never required.

## Core Commands

```bash
sudo systemctl status <service>           # check status + last log lines
sudo systemctl start|stop|restart <service>
sudo systemctl reload <service>           # graceful (not all services support)
sudo systemctl enable|disable <service>   # boot behaviour
sudo systemctl is-active <service>
sudo systemctl is-enabled <service>
```

## Services Quick Reference

| Service | Safe reload? | Notes |
|---------|-------------|-------|
| `nginx` | Yes | Always run `nginx -t` first |
| `apache2` | Yes | Run `apache2ctl configtest` first |
| `mysql` | No | Brief downtime on restart |
| `postgresql` | Yes | reload re-reads postgresql.conf |
| `php8.3-fpm` | Yes | reload finishes active requests |
| `redis` | No | |
| `fail2ban` | Yes | reload re-reads jail configs |
| `certbot.timer` | — | systemd timer, not a daemon |
| `cron` | No | |
| `msmtp` | — | not a daemon; test with command |

Full per-service operations: `references/service-reference.md`

## Viewing Logs (journalctl)

```bash
sudo journalctl -u <service> -n 50 --no-pager     # last 50 lines
sudo journalctl -u <service> -f                   # follow live
sudo journalctl -u <service> --since "1 hour ago"
sudo journalctl -u <service> -p err --no-pager    # errors only
```

## Diagnosing A Crashed Service

```bash
# Step 1: Read exit code and recent logs
sudo systemctl status <service> --no-pager

# Step 2: Get full error context
sudo journalctl -u <service> --since "5 min ago" --no-pager

# Step 3: Test config (web servers)
sudo nginx -t                    # nginx
sudo apache2ctl configtest       # apache2
sudo php-fpm8.3 -t              # php-fpm

# Step 4: Check for disk full or port conflicts
df -h
sudo ss -tlnp | grep <port>
```

## Check All Services At Once

```bash
sudo systemctl list-units --type=service --state=failed
sudo systemctl list-units --type=service --state=running | \
    grep -E "nginx|apache|mysql|postgresql|php|redis|fail2ban"
```

## Node.js Services (Product-Specific)

```bash
# Any Node.js service registered in systemd:
sudo systemctl status <service-name>
sudo journalctl -u <service-name> -n 50 --no-pager
sudo systemctl restart <service-name>    # after code update via update-all-repos
```

For creating a new Node.js systemd unit, see `linux-webstack`.

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-service-management` installs:

| Task | Fast-path script |
|---|---|
| One-screen service status + recent logs | `sudo sk-service-health <service>` |
| Safe restart with pre/post health check | `sudo sk-service-restart <service>` |
| All systemd timers with next/last run | `sudo sk-timer-list` |
| Crontab audit across all users | `sudo sk-cron-audit` |

These are optional wrappers around `systemctl` and `journalctl`.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-service-management
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-service-health | scripts/sk-service-health.sh | yes | Show state, last 20 journal lines, recent restart count, and failed dependencies for a systemd service. |
| sk-cron-audit | scripts/sk-cron-audit.sh | yes | Enumerate all user + system crontabs, verify `MAILTO`, flag jobs that haven't run recently, validate syntax. |
| sk-service-restart | scripts/sk-service-restart.sh | no | Safe restart: check health before, restart, wait, verify, show logs. Rollback hint on failure. |
| sk-timer-list | scripts/sk-timer-list.sh | no | All systemd timers with next and last run, unit, state; flags timers that never fired. |
