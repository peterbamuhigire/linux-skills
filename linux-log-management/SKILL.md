---
name: linux-log-management
description: Read and manage logs on Linux servers across both the Debian/Ubuntu and RHEL families (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). journalctl/journald is identical on both; only the legacy /var/log/* file paths differ. journalctl by service/time/priority. Nginx and Apache log analysis (4xx/5xx spikes, attack patterns, top IPs). fail2ban ban log. MySQL slow queries. PHP errors. Backup cron log. logrotate management. Reference-style with ready-to-run commands.
license: MIT
metadata:
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
`svc_name` from `common.sh`. See [`linux-bash-scripting`](../linux-bash-scripting/SKILL.md)
and [`docs/multi-distro/plan.md`](../docs/multi-distro/plan.md).

## Use when

- Reading service, web, security, or database logs on a Linux server.
- Investigating spikes in errors, attacks, or slow queries.
- Reviewing log rotation or journal storage behavior.

## Do not use when

- The task is general incident routing without a clear symptom; use `linux-troubleshooting`.
- The task is metrics collection or centralized observability setup; use `linux-observability`.

## Required inputs

- The service, path, or time window to inspect.
- The symptom or event type you are trying to explain.
- Any relevant retention or rotation concern.

## Workflow

1. Narrow the target service, path, and timeframe.
2. Use the matching manual commands below to inspect logs and identify patterns.
3. Follow suspicious findings into the owning service or skill.
4. Verify whether the issue is ongoing, resolved, or requires rotation changes.

## Quality standards

- Use time-bounded inspection instead of dumping entire logs.
- Prefer concrete log evidence over speculation.
- Keep rotation and retention changes deliberate.

## Anti-patterns

- Grepping random logs without first identifying the service and timeframe.
- Treating log volume as proof of cause without corroboration.
- Changing rotation settings before understanding the growth source.

## Outputs

- The relevant log evidence and suspected cause.
- Any service or rotation action required next.
- A verification statement showing whether the issue is still reproducing.

## References

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
