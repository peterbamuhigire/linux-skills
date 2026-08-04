---
name: linux-troubleshooting
description: Use when triaging a production Linux incident across CPU, memory, disk, services, web, database, TLS, backups, or deployments; route resource findings to linux-system-monitoring and recovery to linux-disaster-recovery.
license: MIT
metadata:
  portable: true
  compatible_with: [claude-code, codex]
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Troubleshooting

## Distro support

Two-family skill. The diagnosis trees apply to both families; only service
names, log paths, and a few tools differ — plus the RHEL family adds **SELinux**
as a cause of failures that look like permission or connection bugs.

| When diagnosing… | Debian/Ubuntu | RHEL family |
|---|---|---|
| Web server unit | `systemctl status apache2` | `systemctl status httpd` |
| System log | `/var/log/syslog`, `journalctl` | `/var/log/messages`, `journalctl` |
| Auth failures | `/var/log/auth.log` | `/var/log/secure` |
| Web logs | `/var/log/apache2/` | `/var/log/httpd/` |
| Firewall blocking a port | `ufw status` | `firewall-cmd --list-all` |
| Package query | `dpkg -l` / `apt` | `rpm -qa` / `dnf` |

**RHEL-family "it should work but doesn't":** when unix permissions look
correct but you still get 403 / EACCES / "connection refused" from a service
(Apache 403, PHP can't reach the DB, a daemon won't bind a port), suspect
**SELinux** before anything else:

```bash
sudo ausearch -m AVC -ts recent | audit2why     # what did SELinux block, and why
sudo getenforce                                  # Enforcing?
```

Fix with the right context/boolean/port — do **not** `setenforce 0`. See
[`../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md)
and [`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md). In `sk-*`
scripts resolve unit names via `svc_name` from `common.sh`.

## Use when

- A server incident needs symptom-driven diagnosis.
- You know the symptom but not yet the owning subsystem.
- You need a structured triage flow before making changes.
- An unexplained outage needs the failure domain narrowed before remediation.
- Server access is unavailable and the operator needs a read-only diagnostic plan rather than an invented result.

## Do not use when

- The problem is already clearly scoped to one specialist skill.
- The task is proactive monitoring or audit rather than incident response.

<!-- dual-compat-start -->

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---|---|
| Symptom, impact, host/service, and onset | Incident report/monitoring | yes | Gather a broad read-only snapshot; do not guess a branch |
| Recent changes and known-good baseline | Deployment/change records | for cause analysis | State change correlation is unassessed |
| Read/search access to state and logs | System owner | yes | Return safe collection commands only |
| Remediation authority and rollback | Incident/change owner | for mutation | Diagnose and hand off; do not apply fixes |

## Capability Contract

Default triage uses read/search access only. Restarts, deletes, rollbacks, package/config changes, database writes, firewall actions, and recovery operations require explicit authority after evidence identifies the failure mode.

## Degraded Mode

Without logs, history, privileges, network probes, or reproduction, return the most specific supported failure-domain hypothesis and list unassessed branches. Do not close an incident because the symptom temporarily disappears.

## Decision Rules

| Evidence | Action | Failure avoided |
|---|---|---|
| Host-wide resource pressure | Route to monitoring/storage before service restart | Masking the root cause |
| One service failed with valid dependencies | Inspect its config/log/unit | Random system-wide changes |
| RHEL permission failure with correct Unix mode | Check SELinux context/AVCs | Disabling security or chmod escalation |
| Recent deployment aligns with onset | Compare/revert only with authority | Correlation treated as proof |

## Workflow

After the immediate user-visible check, create an incident learning record when the symptom required intervention, repeated, or exposed a runbook gap. Preserve the timeline and before state, name the discriminating evidence, record unknowns, test one bounded countermeasure, and verify rollback/recovery before closure. Standardise the learning in the skill, diagnosis tree, script fixture, or monitoring rule only after the same failed path is exercised.

1. Establish impact, onset, host role, recent changes, and authority; start an evidence timeline.
2. Capture read-only system, socket, service, disk, memory, and relevant log state before intervention.
3. Select one symptom branch and test competing hypotheses with the cheapest discriminating checks.
4. Stop when evidence is insufficient or the branch requires specialist/destructive action.
5. Apply only the authorised minimal fix with explicit success and rollback checks.
6. On failure, recover the previous state, verify the user-visible symptom, and preserve residual evidence.

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| Incident timeline | Records onset, impact, changes, commands, timestamps, and interventions |
| Failure-domain diagnosis | Cites discriminating evidence, alternatives ruled out, and confidence |
| Fix verification | Repeats the user-visible check plus service/resource checks and rollback result |

## Quality standards

- Diagnose from evidence, not intuition.
- Separate triage from final remediation until the failure mode is clear.
- Keep the path short and explicit so incidents stay understandable under pressure.

## Anti-patterns

- Restarting or deleting before triage. Fix: preserve a broad read-only snapshot first.
- Mixing symptom branches without reason. Fix: choose discriminating checks and record why the branch changed.
- Closing on a guess. Fix: repeat the user-visible and subsystem verification checks.
- Treating a recent deployment as proof. Fix: compare timestamps and test alternatives.
- Disabling SELinux to test permissions. Fix: inspect AVCs, labels, and expected policy.
- Applying several fixes at once. Fix: make one bounded change and checkpoint its effect.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Triage summary | Incident commander | States impact, failure domain, confidence, evidence, and gaps |
| Specialist handoff | Owning team | Provides reproducer, timeline, relevant state, and attempted actions |
| Resolution record | Service owner | Shows authorised fix, rollback, user-visible verification, and residual risk |

## Worked Example

For a 502 after deployment, first capture proxy and upstream status, listeners, disk/memory, and matching logs. If Nginx is healthy but PHP-FPM is absent due to invalid config, validate that config and route the bounded service fix; do not restart the whole host.

<!-- dual-compat-end -->

## References

- [`references/diagnosis-tree.md`](references/diagnosis-tree.md)
- [`../../docs/continuous-improvement/incident-learning-standard.md`](../../docs/continuous-improvement/incident-learning-standard.md)
- [`../../docs/continuous-improvement/safe-reversible-operations-standard.md`](../../docs/continuous-improvement/safe-reversible-operations-standard.md)
- [`references/packet-capture-and-tracing.md`](references/packet-capture-and-tracing.md) — `tcpdump` packet capture (BPF filters, pcap, ring buffers) and `strace`/`ltrace`/`lsof` process & file diagnostics
- [`../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md) — SELinux as a hidden cause (RHEL family)

**This skill is self-contained.** Every command below works on a stock
Debian/Ubuntu or RHEL-family server with no additional tooling. The `sk-*` scripts in the
**Optional fast path** section at the bottom are convenience wrappers —
they are never required.

Ask: "What's the symptom?" then follow the matching branch in
`references/diagnosis-tree.md`.

## Symptom Index

| Symptom | Branch |
|---------|--------|
| High CPU or load average | → Branch 1 |
| Out of memory / OOM kill | → Branch 2 |
| Disk full | → Branch 3 |
| Service crashed / won't start | → Branch 4 |
| 502 or 504 from Nginx | → Branch 5 |
| Site is slow | → Branch 6 |
| MySQL problems | → Branch 7 |
| SSL expired or renewal failed | → Branch 8 |
| Backup failed | → Branch 9 |
| Site down after update-all-repos | → Branch 10 |
| Can't reach this server | → Branch 11 |
| Process hung / what's locking this file or port | → Branch 12 |
| Traffic not arriving / SYN-no-ACK / packet capture | → Branch 12 (capture) |

Full diagnosis commands for each: `references/diagnosis-tree.md`

---

## Quick Triage (Run First For Any Issue)

```bash
# System health snapshot
uptime && free -h && df -h

# Failed services
sudo systemctl list-units --type=service --state=failed

# Recent errors across all services
sudo journalctl -p err --since "1 hour ago" --no-pager | head -30

# Nginx error log
sudo tail -20 /var/log/nginx/error.log
```

---

## Most Common Fixes

```bash
# Service crashed → restart it
sudo systemctl restart <service>

# Nginx config broken → find and fix
sudo nginx -t

# Disk full → clear apt cache and vacuum journal
sudo apt clean && sudo journalctl --vacuum-size=500M

# 502 → restart the upstream
sudo systemctl restart php8.3-fpm
sudo systemctl restart apache2

# SSL expired → force renew
sudo certbot renew --force-renewal
```

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-troubleshooting` gives you
interactive decision-tree walkers for each symptom:

| Symptom | Fast-path script |
|---|---|
| High CPU / slow site | `sudo sk-load-investigate` → `sudo sk-why-slow` |
| 502 / 504 | `sudo sk-why-500` |
| Can't reach server | `sudo sk-why-cant-connect` |
| Capture traffic on the wire | `sudo sk-capture --filter 'port 443' --count 200` |

These scripts wrap the manual commands above in a guided walkthrough.
They are optional — the manual commands are always the source of truth.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-troubleshooting
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-load-investigate | scripts/sk-load-investigate.sh | no | Decompose load average: CPU-bound vs I/O-bound vs blocked, top offenders per category. |
| sk-why-slow | scripts/sk-why-slow.sh | no | Decision-tree entry point: walks load/CPU/memory/disk/network/database to diagnose slowness. |
| sk-why-500 | scripts/sk-why-500.sh | no | Decision-tree: PHP-FPM up? Nginx up? error log? permissions? AppArmor? disk full? |
| sk-why-cant-connect | scripts/sk-why-cant-connect.sh | no | Decision-tree: firewall? service listening? DNS? routing? cert expired? rate-limited by fail2ban? |
| sk-capture | scripts/sk-capture.sh | no | Safe bounded `tcpdump -w` capture: forces a packet-count or size/file ring so it can't fill the disk, excludes your SSH session, asks before writing pcap. Read back with `tcpdump -r` / tshark / Wireshark. |
