---
name: linux-log-management
description: Use when inspecting time-bounded journald or service logs, correlating web/database/security events, or managing logrotate retention; use linux-observability for forwarding and linux-troubleshooting for multi-subsystem incidents.
license: MIT
metadata:
  portable: true
  compatible_with: [claude-code, codex]
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Log Management

## Distro support

`journalctl` and the systemd journal are **identical** on both families. The
differences are the legacy `/var/log/*` text-file names and the package
manager. The body uses Debian/Ubuntu paths; the **RHEL family** (Fedora, RHEL,
CentOS Stream, Rocky, Alma, Oracle) equivalents are in the matrix.

| Log / concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| System log (legacy) | `/var/log/syslog` | `/var/log/messages` |
| Auth / sudo / SSH | `/var/log/auth.log` | `/var/log/secure` |
| Mail | `/var/log/mail.log` | `/var/log/maillog` |
| Web (Apache) | `/var/log/apache2/` | `/var/log/httpd/` |
| Cron | `/var/log/syslog` (CRON tag) | `/var/log/cron` |
| systemd journal | `journalctl …` | identical |
| logrotate configs | `/etc/logrotate.d/` | same |
| Package install | `apt install <pkg>` | `dnf install <pkg>` |

**RHEL-family note:** minimal RHEL/Fedora installs may not ship `rsyslog`, so
the legacy `/var/log/*` files may be absent — the journal (`journalctl`) is the
primary source. `journalctl -u <unit>`, `-p err`, `--since` all work the same.

In `sk-*` scripts, prefer `journalctl` (portable) and resolve unit names via
`svc_name` from `common.sh`. See [`linux-bash-scripting`](../../10-automation-and-scripting/linux-bash-scripting/SKILL.md)
and [`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

## Use when

- Reading service, web, security, or database logs on a Linux server.
- Investigating spikes in errors, attacks, or slow queries.
- Reviewing log rotation or journal storage behavior.

## Do not use when

- The task is general incident routing without a clear symptom; use `linux-troubleshooting`.
- The task is metrics collection or centralized observability setup; use `linux-observability`.

<!-- dual-compat-start -->

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---|---|
| Service/path and time window | Incident owner or alert | yes | Stop broad collection and request a bounded target |
| Symptom or event signature | Operator or monitoring evidence | yes | Return an inventory only; do not infer cause |
| Retention and privacy rules | Service owner or policy | for rotation/export | Do not delete, rotate early, or share sensitive records |

## Capability Contract

Read/search access to journals and log files is sufficient for analysis. Rotation changes, vacuuming, deletion, permission changes, and service reloads require explicit authority; shared evidence must redact secrets and personal data.

## Degraded Mode

Fallback when required access is unavailable: report the exact time/source coverage and mark missing periods unassessed. Never equate absent or rotated logs with absence of an event.

## Decision Rules

| Condition | Action | Failure avoided |
|---|---|---|
| Event spans multiple services | Correlate timestamps and request IDs | Single-log attribution error |
| Log growth threatens disk | Preserve incident window, then apply authorised retention | Destroyed evidence |
| Sensitive fields appear | Redact values while retaining timestamp/context | Credential or personal-data exposure |
| Timestamp sources differ | Record timezone/clock offset | False sequence of events |

## Workflow

1. Confirm service, host, timezone, time window, retention, and read/search boundary.
2. Preserve a bounded evidence slice before changing rotation or services.
3. Correlate events across the minimum relevant sources and separate facts from inference.
4. Route the cause to the owning service; stop when evidence cannot distinguish candidates.
5. Apply only authorised rotation/retention changes and validate syntax.
6. On failure, recover the prior logrotate configuration and retain collected evidence.

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| Time-bounded log extract | Names source, host, timezone, command, and redactions |
| Correlation record | Links the conclusion to timestamps/request IDs and states uncertainty |
| Rotation verification | Includes `logrotate` debug/forced-test result and post-change disk state |

## Quality standards

- Use time-bounded inspection instead of dumping entire logs.
- Prefer concrete log evidence over speculation.
- Keep rotation and retention changes deliberate.

## Anti-patterns

- Grepping random logs. Fix: identify service, host, timezone, and timeframe first.
- Treating volume as proof of cause. Fix: correlate content with service behaviour.
- Changing rotation before understanding growth. Fix: measure source and preserve the incident window.
- Publishing raw secrets or tokens. Fix: redact values and retain only useful context.
- Treating rotated logs as proof nothing happened. Fix: mark the missing period unassessed.
- Mixing local and UTC timestamps silently. Fix: normalise or label timezone offsets.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Log finding | Incident owner | States evidence, time coverage, cause/confidence, and gaps |
| Rotation change record | Operations | Shows authorised diff, validation, rollback, and result |
| Specialist handoff | Owning team | Includes the minimum reproducing records without secrets |

## Worked Example

For an Nginx 502 spike from 14:00–14:10 EAT, extract only that access/error interval, correlate upstream errors with PHP-FPM journal entries, and preserve request IDs. If older logs rotated, mark earlier onset unassessed rather than declaring 14:00 the start.

<!-- dual-compat-end -->

## References

- [`../../docs/continuous-improvement/incident-learning-standard.md`](../../docs/continuous-improvement/incident-learning-standard.md)

- [`references/journalctl-reference.md`](references/journalctl-reference.md)
- [`references/log-analysis-patterns.md`](references/log-analysis-patterns.md)
- [`references/log-locations.md`](references/log-locations.md)

**This skill is self-contained.** Every command below is a standard tool on
both the Debian/Ubuntu and RHEL families (only the legacy `/var/log/*` paths
differ — see **Distro support** above). The `sk-*` scripts in the **Optional
fast path** section are convenience wrappers — never required.

## journalctl

```bash
sudo journalctl -u <service> -n 50 --no-pager       # last 50 lines
sudo journalctl -u <service> -f                      # follow live
sudo journalctl -u <service> --since "1 hour ago"
sudo journalctl -p err --since "today" --no-pager    # errors only
sudo journalctl -k --since "today" | grep -i oom     # kernel OOM events
sudo journalctl --disk-usage                         # journal size
```

---

## Nginx Logs

```bash
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log

# HTTP status code distribution:
sudo awk '{print $9}' /var/log/nginx/access.log | sort | uniq -c | sort -rn

# Top IPs by request count:
sudo awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -20

# Recent 5xx errors:
sudo grep '" 5' /var/log/nginx/access.log | tail -20
```

---

## Attack Pattern Detection

```bash
# Login brute-force attempts:
sudo grep -E "POST.*(login|wp-login|admin|xmlrpc)" /var/log/nginx/access.log | \
    awk '{print $1}' | sort | uniq -c | sort -rn | head

# Scanner activity (high 404 rate per IP):
sudo awk '$9 == 404 {print $1}' /var/log/nginx/access.log | \
    sort | uniq -c | sort -rn | head

# Attempts to access sensitive files:
sudo grep -E "\.(env|git|htaccess|sql|bak)" /var/log/nginx/access.log | tail -20
```

---

## fail2ban Log

```bash
sudo tail -f /var/log/fail2ban.log
sudo grep "Ban" /var/log/fail2ban.log | tail -20
sudo grep "$(date '+%Y-%m-%d')" /var/log/fail2ban.log | grep "Ban" | wc -l
```

---

## Other Key Logs

```bash
# PHP errors:
sudo tail -f /var/log/php8.3-fpm.log

# MySQL slow queries:
sudo tail -20 /var/log/mysql/mysql-slow.log 2>/dev/null
mysql -e "SHOW VARIABLES LIKE 'slow_query_log%';" 2>/dev/null

# Apache (port 8080 backend):
sudo tail -f /var/log/apache2/error.log

# Backup cron:
tail -50 ~/backups/mysql/cron.log
```

---

## logrotate

```bash
ls /etc/logrotate.d/                             # existing configs
sudo logrotate -f /etc/logrotate.d/nginx         # force rotate now
sudo logrotate -f /etc/logrotate.d/apache2
```

All log file locations: `references/log-locations.md`

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-log-management` installs:

| Task | Fast-path script |
|---|---|
| Grouped recent errors from journal | `sudo sk-journal-errors --since 1h` |
| Live tail with severity filter | `sudo sk-journal-tail <service>` |
| Access log report (top IPs, 4xx/5xx, bots) | `sudo sk-access-log-report` |
| Error log report (grouped) | `sudo sk-error-log-report` |
| Logrotate config audit | `sudo sk-logrotate-check` |

These are optional wrappers around the manual commands above.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-log-management
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-journal-errors | scripts/sk-journal-errors.sh | yes | Last 24h of `priority<=err` from journal, grouped by service, with counts. |
| sk-access-log-report | scripts/sk-access-log-report.sh | no | Parse Nginx/Apache access logs: top IPs, status code histogram, top URLs, bot ratio. |
| sk-error-log-report | scripts/sk-error-log-report.sh | no | Parse error logs: group by repeated message, severity, timeline. |
| sk-journal-tail | scripts/sk-journal-tail.sh | no | Wrapper over `journalctl -f` with unit filter, severity filter, since-time shorthand, color. |
| sk-logrotate-check | scripts/sk-logrotate-check.sh | no | Verify logrotate configs, show last rotation per config, warn on stale or mis-sized logs. |
