---
name: linux-system-monitoring
description: Use when taking a read-only host-health snapshot or investigating CPU, memory, I/O, network, process, and backup pressure; use linux-observability for persistent telemetry and linux-troubleshooting for incident branching.
license: MIT
metadata:
  portable: true
  compatible_with: [claude-code, codex]
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
[`linux-bash-scripting`](../../10-automation-and-scripting/linux-bash-scripting/SKILL.md) and
[`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

## Use when

- Checking overall host health across CPU, memory, disk, and network.
- Looking for warning signs before or during an incident.
- Verifying backup health as part of routine operations.

## Do not use when

- The task is a specific incident diagnosis with a known symptom; use `linux-troubleshooting`.
- The task is telemetry system design rather than local host inspection; use `linux-observability`.

<!-- dual-compat-start -->

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---|---|
| Host role and observation timeframe | Inventory/incident owner | yes | Return generic command guidance only |
| Symptom, impact, and baseline | Alert, user report, or monitoring history | for diagnosis | Produce a snapshot without causal claim |
| Read/search access | System owner | yes | State monitoring could not be performed |

## Capability Contract

Default mode is read-only using process, kernel, socket, filesystem, and backup status commands. Installing tools, changing priorities/limits, killing processes, tuning kernel values, or restarting services requires explicit authority and a specialist handoff.

## Degraded Mode

If tools, privileges, historical baselines, or repeated samples are unavailable, report the instantaneous measurements and missing context. Do not classify a transient snapshot as sustained health or pressure.

## Decision Rules

| Observation | Action | Failure avoided |
|---|---|---|
| High load with high I/O wait | Inspect devices and blocked tasks | Misdiagnosing storage pressure as CPU |
| Low free memory with healthy available memory | Check reclaim/swap before escalation | False memory alarm |
| Brief spike without sustained impact | Sample across a defined interval | Tuning for noise |
| Backup age exceeds policy | Route to backup owner with timestamp evidence | Silent recovery gap |

## Workflow

1. Confirm host role, clock, symptom, impact, and timeframe.
2. Capture a read-only broad snapshot of load, memory, I/O, sockets, filesystems, processes, and backup age.
3. Sample abnormal resources over time and compare with workload baseline.
4. Correlate metrics before selecting a failure domain; stop when a single snapshot cannot support causality.
5. Route to the owning skill with evidence rather than applying tuning.
6. If collection fails, recover by using available core commands and mark omitted checks unassessed.

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| Host-health snapshot | Includes host, role, timestamps, commands, units, and all core resource areas |
| Pressure diagnosis | Correlates repeated samples with impact and states confidence |
| Specialist handoff | Names the failure domain, reproducing evidence, and unassessed checks |

## Quality standards

- Start broad, then narrow based on evidence.
- Distinguish transient spikes from sustained pressure.
- End with a clear operational conclusion, not just raw command output.

## Anti-patterns

- Tuning before a health snapshot. Fix: collect broad read-only evidence first.
- Treating one metric as the whole story. Fix: correlate load, CPU, memory, I/O, and impact.
- Ignoring backup health. Fix: record last successful backup against policy.
- Reading `free` as free-memory exhaustion. Fix: interpret available memory and reclaim behaviour.
- Calling one spike sustained pressure. Fix: sample across a defined interval.
- Killing a process during monitoring. Fix: hand remediation to an authorised specialist task.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Health summary | On-call operator | States healthy/pressured/unassessed areas with measurements |
| Failure-domain handoff | Specialist owner | Includes timeframe, impact, correlated evidence, and next check |
| Coverage note | Service owner | Identifies missing history, tools, privileges, or backup checks |

## Worked Example

Load average is 12 on an eight-core host, but CPU idle remains 70% and I/O wait is 25%. Repeated `vmstat`/`iostat` samples show blocked tasks on one volume, so route to linux-disk-storage instead of changing CPU limits.

<!-- dual-compat-end -->

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
