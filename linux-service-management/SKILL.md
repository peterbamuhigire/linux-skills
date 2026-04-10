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

## Core Commands

```bash
sudo systemctl status <service>           # check status + last log lines
sudo systemctl start|stop|restart <service>
sudo systemctl reload <service>           # graceful (not all services support)
sudo systemctl enable|disable <service>   # boot behaviour
sudo systemctl is-active <service>
sudo systemctl is-enabled <service>
```

For anything non-trivial, prefer the scripts — they test config before
reloading and roll back on failure:

```bash
sudo sk-service-health <service>        # one-screen status + recent logs
sudo sk-service-restart <service>       # safe restart with health check
sudo sk-timer-list                      # all systemd timers with next/last run
sudo sk-cron-audit                      # all crontabs, MAILTO, last run, syntax
```

## Services Quick Reference

| Service | Safe reload? | Notes |
|---------|-------------|-------|
| `nginx` | Yes | Always run `nginx -t` first (or `sk-nginx-test-reload`) |
| `apache2` | Yes | Run `apache2ctl configtest` first (or `sk-apache-test-reload`) |
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

# Or use the script (color + filter shorthand):
sudo sk-journal-tail <service> --errors --since 1h
```

## Diagnosing A Crashed Service

```bash
# Step 1: Read exit code and recent logs
sudo sk-service-health <service>

# Step 2: Test config (web servers)
sudo nginx -t                    # nginx
sudo apache2ctl configtest       # apache2
sudo php-fpm8.3 -t              # php-fpm

# Step 3: Check for disk full or port conflicts
sudo sk-disk-hogs /
sudo sk-open-ports | grep <port>
```

## Check All Services At Once

```bash
sudo systemctl list-units --type=service --state=failed
sudo systemctl list-units --type=service --state=running | \
    grep -E "nginx|apache|mysql|postgresql|php|redis|fail2ban"
```

## Node.js Services (Product-Specific)

```bash
sudo sk-service-health <service-name>
sudo sk-service-restart <service-name>    # after code update via sk-update-all-repos
```

For creating a new Node.js systemd unit, see `linux-webstack`.

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
