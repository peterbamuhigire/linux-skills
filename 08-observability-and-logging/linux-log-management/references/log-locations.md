# Log File Locations

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

A production Ubuntu/Debian web server writes dozens of logs in dozens of
places. This reference catalogues every log a typical LEMP/LAMP server
produces — what is in it, when to read it, what rotates it, and the
severity patterns to grep for first during an incident. Paths assume
stock Ubuntu 22.04/24.04 with default package layouts; nothing here
requires custom tooling.

## Table of contents

- [Two-tier architecture: journald plus /var/log](#two-tier-architecture-journald-plus-varlog)
- [System logs](#system-logs)
- [Package management logs](#package-management-logs)
- [Boot and cloud-init](#boot-and-cloud-init)
- [Web server logs (Nginx, Apache)](#web-server-logs-nginx-apache)
- [PHP-FPM logs](#php-fpm-logs)
- [Database logs (MySQL, PostgreSQL, Redis)](#database-logs-mysql-postgresql-redis)
- [Mail logs](#mail-logs)
- [Security logs (fail2ban, UFW, audit, Let's Encrypt)](#security-logs-fail2ban-ufw-audit-lets-encrypt)
- [Backup and application logs](#backup-and-application-logs)
- [Log rotation — logrotate quick map](#log-rotation--logrotate-quick-map)
- [Severity patterns to grep for first](#severity-patterns-to-grep-for-first)
- [Sources](#sources)

## Two-tier architecture: journald plus /var/log

Modern Ubuntu logging has two parallel systems:

- **systemd-journald** — binary journal at `/var/log/journal/` (persistent)
  or `/run/log/journal/` (volatile). Everything that runs as a systemd
  unit writes here via its stdout/stderr and via `sd-daemon`. Read it
  with `journalctl`. Indexed, queryable by unit, priority, time, and
  arbitrary metadata fields.
- **rsyslog** — classic text files under `/var/log/`. rsyslog
  (`/etc/rsyslog.conf`, drop-ins in `/etc/rsyslog.d/`) subscribes to the
  journal's forwarded stream and splits it by facility into
  `/var/log/syslog`, `/var/log/auth.log`, `/var/log/kern.log`, etc. Apps
  that were designed before systemd (Nginx, Apache, MySQL, PHP-FPM)
  write their own files directly and ignore journald entirely.

The split is historical, not architectural. In 2024 you can read almost
everything through `journalctl`, but the web and DB stacks still keep
their own files for tooling compatibility (GoAccess, awk pipelines,
logrotate, upstream docs). Treat journald as the source of truth for
system and service-level events and the text files as the source of
truth for web, DB, and app events.

## System logs

| Path | Format | What's in it | When to read |
|---|---|---|---|
| **`journalctl`** (no file) | binary | everything from every systemd unit, kernel ring buffer, login sessions | Default "first look" for any incident |
| **`/var/log/syslog`** | text | rsyslog's general bucket: kernel, cron, systemd, random userspace | Tracing an event that crossed multiple services |
| **`/var/log/auth.log`** | text | sshd, sudo, PAM, login/logout, passwd changes, su | Brute force, unauthorised access, password changes |
| **`/var/log/kern.log`** | text | kernel messages only — OOM kills, hardware errors, iptables/UFW log lines | OOM, disk errors, driver failures |
| **`/var/log/dmesg`** | text | current-boot kernel ring buffer | Boot failures, hardware problems |
| **`/var/log/wtmp`** | binary | login history — read with `last`, `last -f` | `last -30`, `last -f /var/log/btmp` for failed |
| **`/var/log/btmp`** | binary | failed login attempts — `lastb` | Post-incident review |
| **`/var/log/lastlog`** | binary | last login per user — `lastlog` | Dormant account review |
| **`/var/log/faillog`** | binary | failed login counters (legacy) | Rarely — PAM replaced this |
| **`/var/log/alternatives.log`** | text | update-alternatives activity | After tool version changes |

Reading examples:

```bash
sudo journalctl -p err --since "1 hour ago"       # recent errors
sudo tail -f /var/log/auth.log
sudo tail -100 /var/log/syslog | grep -iE "error|fail|denied"
sudo dmesg -T | tail -50                          # human timestamps
last -a | head                                    # last logins
sudo lastb | head                                 # failed logins
```

**auth.log** is the most important file on a public server. Patterns:

- `Failed password for invalid user admin from 198.51.100.4 port 55342`
  → brute force. Fail2ban should be catching it.
- `Accepted publickey for peter from 1.2.3.4 port 52341 ssh2: ED25519`
  → normal successful login; compare IP to expected.
- `sudo:   peter : TTY=pts/0 ; PWD=/home/peter ; USER=root ; COMMAND=/usr/bin/apt update`
  → every sudo invocation is recorded here.

**kern.log** for memory pressure and disk errors:

```bash
sudo grep -i "oom\|killed process" /var/log/kern.log
sudo grep -iE "error|i/o error|EXT4-fs" /var/log/kern.log
```

## Package management logs

| Path | What's in it |
|---|---|
| `/var/log/apt/history.log` | every apt transaction: timestamp, command line, install/upgrade/remove lists |
| `/var/log/apt/term.log` | the actual apt terminal output (dpkg progress) |
| `/var/log/apt/eipp.log.xz` | apt's internal planner trace (compressed) |
| `/var/log/dpkg.log` | every dpkg install/remove/configure event |
| `/var/log/unattended-upgrades/unattended-upgrades.log` | what the auto-updater ran |
| `/var/log/unattended-upgrades/unattended-upgrades-dpkg.log` | dpkg output from auto-updates |
| `/var/log/apt/listchanges.log` | changelogs of upgraded packages (if apt-listchanges installed) |

Rotation: weekly by default via `/etc/logrotate.d/apt`. Kept for 12 weeks.

Debug a package problem:

```bash
# What did apt last do?
grep -A 2 "Start-Date:" /var/log/apt/history.log | tail -20

# Which packages were upgraded yesterday?
awk '/Start-Date: '"$(date -d yesterday +%F)"'/,/End-Date:/' /var/log/apt/history.log

# When was nginx last upgraded?
grep -B1 -A1 "nginx" /var/log/dpkg.log | grep -E "upgrade|install" | tail -5
```

Unattended upgrades are the classic "site broke overnight" culprit. When a
service misbehaves after a reboot, first look at:

```bash
sudo tail -50 /var/log/unattended-upgrades/unattended-upgrades.log
sudo tail -50 /var/log/unattended-upgrades/unattended-upgrades-dpkg.log
```

## Boot and cloud-init

| Path | What's in it |
|---|---|
| `/var/log/boot.log` | systemd boot output (if enabled in rsyslog config) |
| `/var/log/cloud-init.log` | cloud-init's run log (first-boot provisioning) |
| `/var/log/cloud-init-output.log` | stdout/stderr of cloud-init user-data scripts |
| `/var/log/installer/` | every file Ubuntu's installer or live-server wrote on install (`subiquity`) |
| `/var/log/installer/autoinstall-user-data` | the rendered cloud-init user-data |
| `/var/log/installer/subiquity-*.log` | Subiquity installer trace |
| `/var/log/installer/curtin-install.log` | Curtin bootstrap log |

Cloud-init is the first thing to check when a newly provisioned VM is
wrong out of the gate:

```bash
sudo tail -100 /var/log/cloud-init.log
sudo tail -100 /var/log/cloud-init-output.log
sudo cloud-init status --long      # current stage
sudo cloud-init query userdata     # rendered user-data
```

Boot timeline after the fact:

```bash
systemd-analyze time
systemd-analyze blame | head -20
systemd-analyze critical-chain
```

## Web server logs (Nginx, Apache)

| Path | What's in it |
|---|---|
| `/var/log/nginx/access.log` | every HTTP request, default combined format |
| `/var/log/nginx/error.log` | startup errors, config reload messages, 5xx upstream issues, TLS handshake failures, rate limit hits |
| `/var/log/nginx/<domain>.access.log` | per-vhost access log (if configured) |
| `/var/log/nginx/<domain>.error.log` | per-vhost error log (if configured) |
| `/var/log/apache2/access.log` | Apache combined-format requests |
| `/var/log/apache2/error.log` | PHP errors, module errors, authentication failures |
| `/var/log/apache2/other_vhosts_access.log` | catch-all for vhosts that don't set their own |
| `/var/log/apache2/<site>-access.log` | per-vhost |
| `/var/log/apache2/<site>-error.log` | per-vhost |

Rotation: daily via `/etc/logrotate.d/nginx` and `/etc/logrotate.d/apache2`,
14 rotations kept, compressed with gzip. Both configs run a `postrotate`
script that sends `USR1` to the master process so workers reopen the files
without dropping connections.

First commands on a web incident:

```bash
# Live tail both streams:
sudo tail -f /var/log/nginx/access.log /var/log/nginx/error.log

# Recent 5xx only:
sudo grep '" 5[0-9][0-9] ' /var/log/nginx/access.log | tail -30

# Error severity in nginx error.log:
sudo grep -iE "emerg|alert|crit" /var/log/nginx/error.log | tail -20
```

Nginx error severities (lowest to highest): `debug info notice warn error
crit alert emerg`. Default verbosity is `error`; anything at `crit` or
above is page-the-ops-team material.

Common error.log patterns:

| Pattern | Meaning |
|---|---|
| `connect() failed (111: Connection refused) while connecting to upstream` | PHP-FPM / app server down |
| `upstream timed out (110: Connection timed out)` | Upstream slow, often DB-bound |
| `open() "/var/www/.../file" failed (13: Permission denied)` | File perms wrong |
| `SSL_do_handshake() failed (SSL: error)` | TLS negotiation issue |
| `limiting requests, excess: ... by zone` | `limit_req` zone triggered |
| `client intended to send too large body` | `client_max_body_size` too small |
| `worker_connections are not enough` | Increase `worker_connections` |

## PHP-FPM logs

| Path | What's in it |
|---|---|
| `/var/log/php8.3-fpm.log` | master process log: startup, pool restarts, children dying |
| `/var/log/php8.3-fpm.log.1` | rotated |
| `/var/log/php/8.3/fpm/www-slow.log` | slow PHP requests (if `request_slowlog_timeout` set) |
| App-level `error_log` (often `/var/www/<site>/logs/php-error.log`) | `error_log()` output, uncaught exceptions |

Adjust the path to your PHP version. `php7.4` on 20.04, `php8.1` on 22.04,
`php8.3` on 24.04. Discover the running version:

```bash
sudo systemctl list-units 'php*-fpm.service' --state=running
```

FPM pool errors are usually one of:

```
WARNING: [pool www] server reached pm.max_children setting (5), consider raising it
WARNING: [pool www] child N exited on signal 9 (SIGKILL) after X.X seconds from start
ERROR: unable to bind listening socket for address '/run/php/php8.3-fpm.sock': Address already in use
```

"server reached pm.max_children" means FPM is the bottleneck for
throughput. Tune in `/etc/php/8.3/fpm/pool.d/www.conf`:

```
pm = dynamic
pm.max_children = 40
pm.start_servers = 8
pm.min_spare_servers = 4
pm.max_spare_servers = 12
pm.max_requests = 500
request_slowlog_timeout = 2s
slowlog = /var/log/php/8.3/fpm/www-slow.log
```

The slow log is gold for performance debugging:

```bash
sudo tail -100 /var/log/php/8.3/fpm/www-slow.log
```

Each entry shows the PHP backtrace at the moment the request crossed
`request_slowlog_timeout`, so you can see exactly which function call is
blocking (typically a DB query or an HTTP call to a slow upstream).

## Database logs (MySQL, PostgreSQL, Redis)

### MySQL / MariaDB

| Path | What's in it |
|---|---|
| `/var/log/mysql/error.log` | startup, shutdown, InnoDB recovery, replication errors, crash traces |
| `/var/log/mysql/mysql-slow.log` | queries exceeding `long_query_time` (if `slow_query_log=1`) |
| `/var/log/mysql/mysql.log` | general query log (only when explicitly enabled — very noisy) |
| `/var/log/mysql/mariadb.log` | MariaDB default error log name |

Rotation: daily via `/etc/logrotate.d/mysql-server`. A `postrotate` hook
flushes logs with `mysqladmin flush-logs`.

Slow log workflow:

```bash
# Check the slow log is on:
mysql -e "SHOW VARIABLES LIKE '%slow%';"
# slow_query_log                       | ON
# slow_query_log_file                  | /var/log/mysql/mysql-slow.log
# long_query_time                      | 1.000000

# Read the last 20 slow queries:
sudo tail -100 /var/log/mysql/mysql-slow.log

# Summarise — best with mysqldumpslow:
sudo mysqldumpslow -s t -t 10 /var/log/mysql/mysql-slow.log
# -s t = sort by total time, -t 10 = top 10
```

InnoDB error patterns in `error.log`:

- `[ERROR] InnoDB: The total blob data length (...) is greater than 10% of the redo log file size` — bump `innodb_log_file_size`.
- `[ERROR] Out of memory` — `innodb_buffer_pool_size` too high for host RAM.
- `[Warning] Aborted connection X to db:` — client disconnect mid-query.

### PostgreSQL

| Path | What's in it |
|---|---|
| `/var/log/postgresql/postgresql-16-main.log` | all levels; verbosity per `log_min_messages` |
| `/var/log/postgresql/postgresql-16-main.log.1` | rotated |

Version suffix matches the installed major (`14`, `15`, `16`, `17`).

### Redis

| Path | What's in it |
|---|---|
| `/var/log/redis/redis-server.log` | Redis server output (when `logfile` is set in `redis.conf`) |
| journalctl `-u redis-server.service` | if `logfile ""` (stdout → journal) |

Ubuntu packages write to the file; upstream Docker image writes to stdout.
Check which mode you are in before hunting logs.

## Mail logs

| Path | What's in it |
|---|---|
| `/var/log/mail.log` | everything mail-related: postfix, dovecot, opendkim, spamassassin |
| `/var/log/mail.err` | mail errors only (rsyslog filter) |
| `/var/log/mail.warn` | mail warnings (rsyslog filter) |
| `/var/log/dovecot.log` | Dovecot (if configured separately) |
| `/var/log/dovecot-info.log` | Dovecot info-level |

A successful outbound delivery produces the classic five-line sequence:

```
postfix/pickup[...]: 1234567: uid=33 from=<www-data>
postfix/cleanup[...]: 1234567: message-id=<...>
postfix/qmgr[...]: 1234567: from=<sender@example.com>, size=4321, nrcpt=1
postfix/smtp[...]: 1234567: to=<recipient@example.net>, relay=..., status=sent (250 ok)
postfix/qmgr[...]: 1234567: removed
```

`status=deferred` or `status=bounced` is a failure; the quoted remote
response (everything inside the parentheses) tells you why.

Failed auth attempts on submission:

```bash
sudo grep -i "authentication fail" /var/log/mail.log | tail
sudo grep "SASL" /var/log/mail.log | tail
```

## Security logs (fail2ban, UFW, audit, Let's Encrypt)

| Path | What's in it |
|---|---|
| `/var/log/fail2ban.log` | every jail action: Found, Ban, Unban, restart |
| `/var/log/ufw.log` | every blocked packet (if UFW logging is on) — prefix `[UFW BLOCK]` |
| `/var/log/audit/audit.log` | auditd kernel audit events (syscalls, file watches) |
| `/var/log/letsencrypt/letsencrypt.log` | certbot's run log — renewals, errors |
| `/var/log/sssd/*` | SSSD if you use LDAP/AD login |
| `/var/log/apparmor*` | AppArmor denials (also in journald) |

### fail2ban

```bash
sudo tail -f /var/log/fail2ban.log
sudo grep "Ban " /var/log/fail2ban.log | tail
sudo grep "$(date '+%Y-%m-%d')" /var/log/fail2ban.log | grep -c "Ban "
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

Entries:

- `[sshd] Found 198.51.100.9 - 2025-03-22 04:55:01` — match against a
  filter regex.
- `[sshd] Ban 198.51.100.9` — jail threshold exceeded.
- `[sshd] Unban 198.51.100.9` — bantime expired.

### UFW

Each blocked packet emits:

```
[UFW BLOCK] IN=eth0 OUT= MAC=... SRC=203.0.113.7 DST=10.0.0.5 LEN=60 TTL=54 PROTO=TCP SPT=55432 DPT=23
```

Top attacker IPs:

```bash
sudo awk '/\[UFW BLOCK\]/ {for(i=1;i<=NF;i++) if($i ~ /^SRC=/) print substr($i,5)}' /var/log/ufw.log \
  | sort | uniq -c | sort -rn | head -20
```

### auditd

```bash
sudo ausearch -ts today -m USER_LOGIN        # today's logins
sudo ausearch -k passwd_changes              # by watch key
sudo aureport --auth --summary               # auth summary
sudo aureport --file --summary               # file access summary
```

### Let's Encrypt

```bash
sudo tail -100 /var/log/letsencrypt/letsencrypt.log
sudo grep -E "Renew|error|Failed" /var/log/letsencrypt/letsencrypt.log | tail
```

## Backup and application logs

Paths here depend on your conventions. The patterns seen in this repo's
other skills:

| Path | What's in it |
|---|---|
| `~/backups/mysql/cron.log` | mysqldump cron output |
| `/backups/<app>/cron.log` | per-app backup cron |
| `~/.backup-encryption-key` | GPG key (file, not log — mode 600) |
| `/var/log/rclone.log` | rclone sync output |
| `/var/www/<site>/storage/logs/laravel.log` | Laravel app log |
| `/var/www/<site>/current/log/production.log` | Rails production log |
| `pm2 logs` or `~/.pm2/logs/<app>-out.log` | Node.js via PM2 |
| `journalctl -u <app>.service` | Node/Go/Rust apps launched as systemd units |

Always write app logs somewhere logrotate knows about. A Laravel log
file growing past a few GB is a classic "why is my disk full" culprit.

## Log rotation — logrotate quick map

logrotate is invoked daily from `/etc/cron.daily/logrotate` and reads:

- `/etc/logrotate.conf` — global defaults
- `/etc/logrotate.d/*` — per-package drop-ins

Inspect configs:

```bash
ls /etc/logrotate.d/
sudo cat /etc/logrotate.d/nginx
sudo cat /etc/logrotate.d/apache2
sudo cat /etc/logrotate.d/mysql-server
```

Force a rotation right now (for a single config):

```bash
sudo logrotate -f /etc/logrotate.d/nginx
```

Dry run — show what would happen without touching files:

```bash
sudo logrotate -d /etc/logrotate.d/nginx 2>&1 | head -40
```

See when a config last ran:

```bash
sudo cat /var/lib/logrotate/status | head
# "/var/log/nginx/access.log" 2025-03-22
```

A typical Nginx stanza:

```
/var/log/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    prerotate
        if [ -d /etc/logrotate.d/httpd-prerotate ]; then \
            run-parts /etc/logrotate.d/httpd-prerotate; \
        fi \
    endscript
    postrotate
        invoke-rc.d nginx rotate >/dev/null 2>&1
    endscript
}
```

Key directives:

- **`daily` / `weekly` / `monthly`** — schedule.
- **`rotate N`** — keep N old files.
- **`compress` / `delaycompress`** — gzip rotated files; `delay` keeps the
  most recent rotation uncompressed (easier live tailing after rotate).
- **`create MODE user group`** — create a fresh empty file with the right
  owner and perms after rotation.
- **`sharedscripts`** — run postrotate once per group, not once per file.
- **`postrotate`** — signal the service so it reopens the new file. Nginx
  uses `USR1`; Apache uses `graceful`; MySQL uses `flush-logs`.

A log that rotates but keeps being written to by the old handle (common
with apps that never receive a signal) will eventually blow up the disk
because the old inode stays open. The fix is `copytruncate`:

```
/var/www/myapp/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate     # safe for apps that do not handle a reopen signal
}
```

`copytruncate` copies the file then truncates in place, so the app keeps
writing but the file size resets.

## Severity patterns to grep for first

When you walk up to an unfamiliar server and something is wrong, run
these in order:

```bash
# 1. Failed services:
sudo systemctl list-units --type=service --state=failed

# 2. Recent errors anywhere:
sudo journalctl -p err --since "1 hour ago" --no-pager | tail -30

# 3. Kernel / OOM / disk errors:
sudo journalctl -k --since "1 hour ago" | grep -iE "oom|error|killed|ext4|nvme"

# 4. Web 5xx:
sudo grep '" 5[0-9][0-9] ' /var/log/nginx/access.log | tail -30

# 5. Web critical errors:
sudo grep -iE "emerg|alert|crit" /var/log/nginx/error.log | tail -20

# 6. PHP crash or slow:
sudo tail -50 /var/log/php*-fpm.log
sudo tail -30 /var/log/php/*/fpm/www-slow.log 2>/dev/null

# 7. Auth brute force:
sudo tail -50 /var/log/auth.log | grep -iE "fail|invalid"

# 8. Fail2ban bans:
sudo tail -30 /var/log/fail2ban.log | grep Ban

# 9. Apt last activity:
grep -A 2 "Start-Date:" /var/log/apt/history.log | tail -10

# 10. Cloud-init (if freshly provisioned):
sudo tail -50 /var/log/cloud-init-output.log
```

These ten commands usually surface the cause of whatever you are
investigating. Pair with `references/journalctl-reference.md` for deep
journal queries and `references/log-analysis-patterns.md` for
access-log number-crunching.

## Sources

- Canonical, *Ubuntu Server Guide* (20.04 LTS), logging and rsyslog
  sections.
- Ghada Atef, *Mastering Ubuntu* (2023), system administration chapter.
- `man 5 logrotate`, `man 1 journalctl`, `man 8 rsyslogd`.
- systemd-journald documentation —
  <https://www.freedesktop.org/software/systemd/man/systemd-journald.service.html>.
- Nginx logging —
  <https://nginx.org/en/docs/http/ngx_http_log_module.html>.
- Apache logging —
  <https://httpd.apache.org/docs/2.4/logs.html>.
- MySQL slow query log —
  <https://dev.mysql.com/doc/refman/8.0/en/slow-query-log.html>.
