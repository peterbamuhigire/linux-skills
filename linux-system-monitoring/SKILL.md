---
name: linux-system-monitoring
description: Monitor system health on Ubuntu/Debian production servers. CPU load, memory, disk I/O, network connections, process inspection. Covers htop, iostat, vmstat, ss, and backup health verification. Includes what warning signs to watch for. Reference-style — outputs commands and how to read them.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# System Monitoring

## Quick Health Check

```bash
sudo sk-system-health      # single-screen snapshot: load, CPU, mem, swap, disk, top procs
sudo sk-open-ports         # ss -tulnp with per-port risk notes
sudo sk-swap-check         # swap usage, swappiness, top swap consumers
```

Manual equivalents below for reference.

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
sudo sk-open-ports        # preferred — pretty output + risk hints
ss -tunapl                # all connections with process
ss -tan | awk '{print $1}' | sort | uniq -c | sort -rn   # count by state
```

## Backup Health

```bash
sudo sk-backup-verify      # backup age + integrity + remote reachable
```

Full command reference with output interpretation: `references/monitoring-commands.md`

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
