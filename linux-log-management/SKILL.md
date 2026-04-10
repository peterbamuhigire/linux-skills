---
name: linux-log-management
description: Read and manage logs on Ubuntu/Debian servers. journalctl by service/time/priority. Nginx and Apache log analysis (4xx/5xx spikes, attack patterns, top IPs). fail2ban ban log. MySQL slow queries. PHP errors. Backup cron log. logrotate management. Reference-style with ready-to-run commands.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Log Management

## journalctl

```bash
# Fast paths via scripts:
sudo sk-journal-errors --since 1h        # priority <= err, grouped by service
sudo sk-journal-tail <service> --errors  # live tail with severity filter

# Manual commands:
sudo journalctl -u <service> -n 50 --no-pager       # last 50 lines
sudo journalctl -u <service> -f                      # follow live
sudo journalctl -u <service> --since "1 hour ago"
sudo journalctl -p err --since "today" --no-pager    # errors only
sudo journalctl -k --since "today" | grep -i oom     # kernel OOM events
sudo journalctl --disk-usage                         # journal size
```

---

## Nginx / Apache Logs

```bash
# Structured reports:
sudo sk-access-log-report --server nginx --top 20
sudo sk-error-log-report --server nginx --since 1h

# Manual:
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
sudo sk-fail2ban-status              # jails, active bans, recent blocks
sudo tail -f /var/log/fail2ban.log
sudo grep "Ban" /var/log/fail2ban.log | tail -20
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
sudo sk-logrotate-check                          # verify config + last rotation per config
ls /etc/logrotate.d/                             # existing configs
sudo logrotate -f /etc/logrotate.d/nginx         # force rotate now
sudo logrotate -f /etc/logrotate.d/apache2
```

All log file locations: `references/log-locations.md`

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
