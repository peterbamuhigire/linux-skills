---
name: linux-system-monitoring
description: Monitor system health on Debian/Ubuntu and the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) production servers. Monitoring commands are identical across both families; only install steps and a couple of package names differ. CPU load, memory, disk I/O, network connections, process inspection. Covers htop, iostat, vmstat, ss, and backup health verification. Includes what warning signs to watch for. Reference-style — outputs commands and how to read them.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# System Monitoring

## Distro support

Monitoring commands are **identical** on both families — `top`, `htop`, `ss`,
`vmstat`, `iostat`, `free`, `uptime`, `ps`, `sar` behave the same. The only
differences are how the tools are installed and a couple of package names. Body
uses Debian/Ubuntu; the **RHEL family** (Fedora, RHEL, CentOS Stream, Rocky,
Alma, Oracle) equivalents are in the matrix.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Install a tool | `apt install htop sysstat` | `dnf install htop sysstat` |
| sysstat package | `sysstat` | `sysstat` (enable `sysstat.service`) |
| Process/socket/mem tools | `ps`, `ss`, `free`, `vmstat` | identical |
| Service health | `systemctl status` / `journalctl` | identical |
| Firewall used for port checks | `ufw` | `firewalld` |

In `sk-*` scripts use the `common.sh` primitives (`pkg_install`, `svc_name`,
`firewall_allow`) instead of hardcoding the family. See
[`linux-bash-scripting`](../linux-bash-scripting/SKILL.md) and
[`docs/multi-distro/plan.md`](../docs/multi-distro/plan.md).

## Use when

- Checking overall host health across CPU, memory, disk, and network.
- Looking for warning signs before or during an incident.
- Verifying backup health as part of routine operations.

## Do not use when

- The task is a specific incident diagnosis with a known symptom; use `linux-troubleshooting`.
- The task is telemetry system design rather than local host inspection; use `linux-observability`.

## Required inputs

- The host and timeframe of interest.
- Any symptom or suspected pressure area.
- Whether the goal is a quick health snapshot or a deeper subsystem review.

## Workflow

1. Capture a quick health snapshot first.
2. Drill into the resource area showing abnormal behavior.
3. Compare the observed metrics to the warning signs reference.
4. Hand off to the owning skill when the issue becomes service-, storage-, or network-specific.

## Quality standards

- Start broad, then narrow based on evidence.
- Distinguish transient spikes from sustained pressure.
- End with a clear operational conclusion, not just raw command output.

## Anti-patterns

- Jumping into deep tuning before a basic health snapshot.
- Treating one abnormal metric as the whole story.
- Ignoring backup-health checks during routine host reviews.

## Outputs

- A host-health snapshot and identified pressure points.
- The commands used to confirm or rule out resource contention.
- The next owning skill or remediation direction when deeper work is needed.

## References

- [`references/monitoring-commands.md`](references/monitoring-commands.md)
- [`references/warning-signs.md`](references/warning-signs.md)

**This skill is self-contained.** Every command below is a standard tool on
both families (Debian/Ubuntu and the RHEL family); only the install step and a
couple of package names differ — see **Distro support** above. The `sk-*`
scripts in the **Optional fast path** section are convenience wrappers — never
required.

## Quick Health Check

```bash
echo "=LOAD=" && uptime && \
echo "=MEMORY=" && free -h && \
echo "=DISK=" && df -h && \
echo "=SERVICES=" && \
  for s in nginx mysql php8.3-fpm apache2 fail2ban; do
    printf "%-20s %s\n" $s $(systemctl is-active $s 2>/dev/null)
  done && \
echo "=LAST BACKUP=" && ls -lt ~/backups/ 2>/dev/null | head -3
```

---

## CPU & Load

```bash
uptime                    # load: 1m 5m 15m — concern if sustained > nproc
nproc                     # CPU core count
htop                      # P=CPU sort, M=memory sort, q=quit
top -bn1 | head -20       # non-interactive snapshot
ps aux --sort=-%cpu | head -10
```

## Memory

```bash
free -h
# No swap = OOM kill fires when available → 0
ps aux --sort=-%mem | head -10
```

## Disk I/O

```bash
iostat -x 1 5             # %util > 80% = bottleneck, await > 50ms = slow disk
sudo iotop -bod 5         # per-process I/O (requires: apt install iotop)
```

## Network

```bash
ss -tunapl                # all connections with process
ss -tan | awk '{print $1}' | sort | uniq -c | sort -rn   # count by state
ss -tlnp                  # listening services
```

## Backup Health

```bash
crontab -l | grep -i backup                      # backup cron present?
find ~/backups -name "*.gpg" -mtime -3 2>/dev/null | wc -l  # backups in 3 days
rclone about gdrive: 2>/dev/null | head -2       # remote reachable?
```

Full command reference with output interpretation: `references/monitoring-commands.md`

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-system-monitoring` installs:

| Task | Fast-path script |
|---|---|
| One-screen health snapshot | `sudo sk-system-health` |
| Listening ports with risk notes | `sudo sk-open-ports` |
| Swap usage and swappiness check | `sudo sk-swap-check` |

These wrap the manual commands above — optional.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-system-monitoring
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-system-health | scripts/sk-system-health.sh | yes | One-screen snapshot: load, CPU, mem, swap, disk, top 5 processes, uptime. |
| sk-open-ports | scripts/sk-open-ports.sh | yes | `ss -tulnp` pretty output with per-port risk notes (e.g. MySQL on 0.0.0.0 flagged). |
| sk-swap-check | scripts/sk-swap-check.sh | no | Swap usage, swappiness, top swap consumers, recommend adjustments. |
