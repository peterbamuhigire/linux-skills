---
name: linux-service-management
description: Manage systemd services on both Debian/Ubuntu and RHEL-family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) servers. systemd itself is identical across both families — only a few unit names and the package manager differ. Start, stop, restart, reload, enable/disable on boot, view status and logs via journalctl. Covers all web server services (nginx, apache2/httpd, mysql/mariadb, postgresql, php-fpm, redis, fail2ban, certbot, cron/crond, msmtp) and Node.js product services. Includes crashed-service diagnosis workflow.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Service Management

## Distro support

systemd is **identical** on both supported families — `systemctl`, `journalctl`,
unit files, targets, and timers all work the same. The only differences are a
few **unit names** and the package manager. The commands below use the
Debian/Ubuntu names; the **RHEL family** (Fedora, RHEL, CentOS Stream, Rocky,
Alma, Oracle) equivalents are in the matrix.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Web server unit | `apache2` | `httpd` |
| Cron daemon unit | `cron` | `crond` |
| SSH daemon unit | `ssh` | `sshd` |
| Database unit | `mysql` / `mariadb` | `mariadb` |
| Firewall unit | `ufw` | `firewalld` |
| Install a service pkg | `apt install <pkg>` | `dnf install <pkg>` |
| systemctl / journalctl | identical | identical |
| Unit file locations | `/etc/systemd/system`, `/lib/systemd/system` | same |
| Targets (`multi-user`/`graphical`) | identical | identical |
| cgroup v2 resource control (`CPUWeight=`, `CPUQuota=`, `IOWeight=`, `MemoryMax=`) | identical | identical |
| `nice` / `renice` / `ionice` | identical | identical |

In `sk-*` scripts, resolve unit names with the `svc_name` helper from
`common.sh` (e.g. `svc_name apache` → `apache2` or `httpd`) instead of
hardcoding — see [`linux-bash-scripting`](../../10-automation-and-scripting/linux-bash-scripting/SKILL.md) and
[`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

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
- [`references/resource-control-and-targets.md`](references/resource-control-and-targets.md)

**This skill is self-contained.** Every command below is a standard systemd
tool that works identically on both the Debian/Ubuntu and RHEL family (Fedora,
RHEL, CentOS Stream, Rocky, Alma, Oracle) — only the unit names in the **Distro
support** matrix differ. The `sk-*` scripts in the **Optional fast path**
section are convenience wrappers — never required.

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

## Process Priority & cgroup Resource Control

A background service must never starve the host. systemd runs every service
in a **cgroup v2** control group, so you can cap its CPU, I/O, and memory.

```bash
# Ad-hoc, per-process: nice (CPU) + ionice (disk I/O)
nice -n 10 /usr/local/bin/backup.sh          # lower CPU priority (-20 high .. 19 low)
sudo renice -n 10 -p <pid>                    # re-prioritize a running process
ionice -c 3 /usr/local/bin/backup.sh          # idle I/O class — yields the disk
nice -n 19 ionice -c 3 /usr/local/bin/heavy.sh

# Per-service, persistent, kernel-enforced — via the unit [Service] section:
#   Nice=10               CPUWeight=20        CPUQuota=50%
#   IOSchedulingClass=idle  IOWeight=20       MemoryMax=512M  TasksMax=64

# Apply a limit to a running service without editing the unit:
sudo systemctl set-property nginx.service CPUQuota=50% MemoryMax=512M
sudo systemctl set-property --runtime mysql.service IOWeight=50   # until reboot

# Inspect effective limits + live usage:
systemctl show nginx.service -p CPUWeight -p CPUQuota -p MemoryMax
systemd-cgtop                                 # top-like per-cgroup usage
```

`CPUWeight=`/`IOWeight=` are relative shares under contention; `CPUQuota=`/
`MemoryMax=` are hard ceilings. See
[`references/resource-control-and-targets.md`](references/resource-control-and-targets.md)
for the full directive table and a worked resource-limited service.

## systemd Targets (boot state & ordering)

Targets are the modern replacement for SysV runlevels — a group of units
that defines the system state.

```bash
systemctl get-default                          # current boot target
sudo systemctl set-default multi-user.target   # boot headless (no GUI) — server default
sudo systemctl set-default graphical.target    # boot into a desktop
sudo systemctl isolate rescue.target           # switch state live (single-user repair)
systemctl list-units --type=target             # active targets
systemctl list-dependencies multi-user.target  # what boots in this target
```

| Target | Runlevel | Meaning |
|---|---|---|
| `multi-user.target` | 3 | Full system, **no GUI** — normal server default |
| `graphical.target`  | 5 | multi-user **plus** a graphical login |
| `rescue.target`     | 1 | Single-user repair mode |

Dependency ordering in a unit: `Wants=` (soft) / `Requires=` (hard) pull a
dependency in; `After=`/`Before=` order startup (ordering is **separate** from
requirement); `[Install] WantedBy=multi-user.target` is what `systemctl
enable` hooks into to start the service at boot. Details in
[`references/resource-control-and-targets.md`](references/resource-control-and-targets.md).

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
| Show or cap a service's CPU/IO/memory limits | `sudo sk-service-priority <service> [--cpu-quota 50% --memory-max 512M]` |

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
| sk-service-priority | scripts/sk-service-priority.sh | no | Show a service's effective cgroup limits (CPUWeight/CPUQuota/IOWeight/MemoryMax/Nice) and live usage; with limit flags, applies them via `systemctl set-property` (asks first) so a background service can't starve the host. |
