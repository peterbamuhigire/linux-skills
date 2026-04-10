# Troubleshooting diagnosis tree

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This is the full symptom-driven decision tree for an Ubuntu/Debian production
web server running Nginx + Apache (8080) + PHP-FPM + MySQL + Redis. Each
branch starts with a symptom, walks the commands to pin down the cause, and
points at the fix. Every command works on a stock server with no `sk-*`
scripts installed.

Rule of thumb: **always start with a 30-second universal snapshot**, then
pick the branch. Don't dive into a branch without first ruling out the
obvious wide-scope problems (disk full, service dead, OOM kill).

## Table of contents

- [30-second universal snapshot](#30-second-universal-snapshot)
- [Branch 1: High CPU / load average](#branch-1-high-cpu--load-average)
- [Branch 2: Out of memory / OOM kill](#branch-2-out-of-memory--oom-kill)
- [Branch 3: Disk full](#branch-3-disk-full)
- [Branch 4: Service crashed or won't start](#branch-4-service-crashed-or-wont-start)
- [Branch 5: 502 / 504 Bad Gateway from Nginx](#branch-5-502--504-bad-gateway-from-nginx)
- [Branch 6: Site is slow](#branch-6-site-is-slow)
- [Branch 7: MySQL problems](#branch-7-mysql-problems)
- [Branch 8: SSL expired or renewal failed](#branch-8-ssl-expired-or-renewal-failed)
- [Branch 9: Backup failed](#branch-9-backup-failed)
- [Branch 10: Site down after update-all-repos](#branch-10-site-down-after-update-all-repos)
- [Branch 11: Can't reach the server](#branch-11-cant-reach-the-server)
- [Branch 12: Strace / process tracing](#branch-12-strace--process-tracing)
- [Branch 13: Security audit — who touched what](#branch-13-security-audit--who-touched-what)
- [Sources](#sources)

---

## 30-second universal snapshot

Run this first, for *any* symptom. It rules out the 80% case in 30 seconds.

```bash
uptime                                              # load averages
free -h                                             # memory + swap
df -h                                               # filesystems
sudo systemctl list-units --type=service --state=failed   # failed units
sudo journalctl -p err --since "1 hour ago" --no-pager | head -30
```

Interpretation:

- **Load averages > number of CPU cores sustained** → Branch 1.
- **"available" memory near 0 AND swap growing** → Branch 2.
- **Any filesystem > 90%** → Branch 3.
- **Any failed service** → Branch 4.
- **Repeated err-level entries from one service** → Branch 4 + check that service directly.

---

## Branch 1: High CPU / load average

### Symptoms
- `uptime` shows 1m load > cores sustained for minutes.
- `top` or `htop` shows one or more processes at 90%+ CPU.
- Site feels slow (also Branch 6).

### Diagnostic sequence

```bash
uptime                                              # the actual load
nproc                                               # CPU cores (compare load to this)
top -bn1 | head -20                                 # non-interactive top
ps aux --sort=-%cpu | head -10                      # top CPU consumers
ps -eo pid,comm,state,pcpu,pmem --sort=-pcpu | head # with state column (D = I/O wait)
```

If the `S` column has many `D` states → this is I/O-bound, not CPU-bound.
Skip to the disk check:

```bash
iostat -x 1 5                                       # %util > 80% = disk bottleneck
sudo iotop -bod 5                                   # per-process I/O (apt install iotop)
```

### Root causes in order of frequency

1. **Runaway PHP-FPM workers** — usually stuck waiting on MySQL.
2. **MySQL slow query consuming a thread** — see Branch 7.
3. **A cron job colliding with peak traffic** — check `crontab -l` and `/etc/cron.*/`.
4. **Scraper or scripted attack hitting expensive endpoints** — see Branch 6, top IPs.
5. **Backup running during business hours** — check `~/backups/mysql/cron.log`.
6. **Kernel task like `kworker` or `jbd2`** — usually filesystem journaling under I/O load; tuning commit interval helps, replacing the disk helps more.

### Fixes

```bash
sudo systemctl restart php8.3-fpm                   # clear runaway workers
sudo systemctl restart apache2                      # clear stuck Apache children
kill -9 <pid>                                       # last resort for a single process
sudo nice -n 19 ionice -c 3 <cmd>                   # deprioritize a noisy job
```

---

## Branch 2: Out of memory / OOM kill

### Symptoms
- A service vanishes without a clean shutdown.
- `dmesg` or journal mentions "oom-killer" or "Killed process".
- `free -h` shows available memory near zero.

### Diagnostic sequence

```bash
free -h
sudo dmesg -T | grep -i -E "oom|killed process" | tail -10
sudo journalctl -k --since "1 hour ago" | grep -i -E "oom|killed"
ps aux --sort=-%rss | head -10                      # top memory consumers
```

To find the moment and what was killed:

```bash
sudo journalctl --since "today" | grep -i "out of memory" | tail -20
```

Check swap behavior:

```bash
cat /proc/swaps                                     # is swap configured at all?
sysctl vm.swappiness                                # default 60; 10 is better on a server
vmstat 1 5                                          # si/so columns — real swap activity
```

### Root causes

1. **PHP-FPM `pm.max_children` too high** — each worker can consume hundreds of MB; `workers × per-worker RAM > system RAM` → OOM.
2. **MySQL `innodb_buffer_pool_size` too large** relative to RAM (+ overhead from other caches).
3. **A memory-leaking application (PHP, Node.js)** — restart recovers; long-term fix needs code.
4. **No swap file** on a small server — see `linux-disk-storage` for swapfile setup.
5. **Runaway log or query aggregation** buffering results in memory.

### Fixes

```bash
# Immediate — restart whatever was killed
sudo systemctl restart <service>

# Add swap if none exists (short-term buffer)
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
sudo sysctl vm.swappiness=10
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.d/99-swappiness.conf

# Tune PHP-FPM — lower pm.max_children (see linux-webstack)
sudo nano /etc/php/8.3/fpm/pool.d/www.conf

# Tune MySQL innodb_buffer_pool_size (see linux-webstack)
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
```

---

## Branch 3: Disk full

### Symptoms
- Services fail writes: "No space left on device" in logs.
- MySQL stops accepting writes.
- Nginx can't rotate logs.
- `df -h` shows a filesystem at 100%.

### Diagnostic sequence

```bash
df -h                                               # which filesystem?
df -i                                               # inode usage (a separate way to be full)
du -sh /var/* 2>/dev/null | sort -rh | head -10     # top consumers in /var
du -sh /home/* 2>/dev/null | sort -rh | head -10
du -sh /var/log/* 2>/dev/null | sort -rh | head -10
du -sh /var/www/* 2>/dev/null | sort -rh | head -10
sudo find / -type f -size +100M 2>/dev/null | head -20
```

### Immediate reclaim (safe)

```bash
sudo apt clean                                      # always safe
sudo apt autoremove                                 # removes unneeded deps
sudo journalctl --vacuum-size=500M                  # keeps recent, drops old
sudo find /tmp /var/tmp -type f -mtime +7 -delete   # old temp files
```

### Deeper reclaim

```bash
# Old kernel images (verify current kernel first)
uname -r
sudo apt autoremove --purge

# Docker buildup
docker system prune                                 # safe
docker system prune -a                              # aggressive — reads instructions first

# Truncate an oversize log without breaking the writer
sudo truncate -s 0 /var/log/<oversize.log>

# Old backup files (respect retention!)
find ~/backups -name "*.gpg" -mtime +7 -delete
```

### If inodes are full (`df -i`)

Inodes can be exhausted even with free space. Common sources:

```bash
sudo find /var/lib/php/sessions/ -type f | wc -l    # PHP sessions
sudo find /var/spool/postfix/ -type f | wc -l       # mail queue
sudo find /tmp -type f | wc -l                      # stale temp files

# Clean up:
sudo find /var/lib/php/sessions/ -type f -mmin +1440 -delete
sudo postsuper -d ALL                               # flush mail queue (confirm first)
```

---

## Branch 4: Service crashed or won't start

### Symptoms
- `systemctl status <service>` says `failed` or `inactive (dead)`.
- Service wrote a stack trace to the journal.
- Listener port not present.

### Diagnostic sequence

```bash
sudo systemctl status <service> --no-pager          # state + recent log + exit code
sudo journalctl -u <service> --since "10 min ago" --no-pager
sudo journalctl -u <service> -p err --no-pager | tail -20
```

Confirm it's really down:

```bash
sudo systemctl is-active <service>
sudo systemctl is-enabled <service>                 # will it start on boot?
ps aux | grep <service-name>
ss -tlnp | grep :<port>
```

### Validate config for web stack services

```bash
sudo nginx -t                                       # nginx
sudo apache2ctl configtest                          # apache2
sudo php-fpm8.3 -t                                  # php-fpm
sudo sshd -t                                        # sshd
sudo named-checkconf                                # bind9
sudo postfix check                                  # postfix
```

A `configtest` failure is the most common cause after a config edit. Fix
the config, test, then restart.

### Other common causes

1. **Port conflict** — another process is already on the port.
   ```bash
   sudo ss -tlnp | grep :<port>
   sudo lsof -i :<port>
   ```
2. **Missing dependency** — recent package update removed a library.
   ```bash
   sudo journalctl -u <service> | grep -i -E "error while loading|cannot open shared"
   ```
3. **Permissions broke** — socket dir not writable by the service user.
   ```bash
   ls -la /run/<service>*
   ls -la /var/lib/<service>
   ```
4. **Disk full** — Branch 3.
5. **OOM kill on start** — Branch 2.

### Recovery

```bash
# Once the root cause is fixed:
sudo systemctl restart <service>
sudo systemctl status <service> --no-pager
sudo journalctl -u <service> -n 30 --no-pager

# If the unit file itself was edited
sudo systemctl daemon-reload
sudo systemctl restart <service>
```

---

## Branch 5: 502 / 504 Bad Gateway from Nginx

### Symptoms
- `curl https://example.com` returns 502 or 504.
- Nginx error log: "upstream prematurely closed connection" or "connect() to
  unix:/run/php/php8.3-fpm.sock failed".

### Diagnostic sequence

```bash
sudo tail -30 /var/log/nginx/error.log              # what exactly failed?
sudo systemctl status nginx
sudo systemctl status php8.3-fpm                    # direct-PHP sites
sudo systemctl status apache2                       # PHP-via-Apache sites
ls -la /run/php/php8.3-fpm.sock                     # socket should exist, owned by www-data
ss -tlnp | grep 8080                                # apache on its backend port?
```

### Common signatures and fixes

**"connect() to unix:/run/php/php8.3-fpm.sock failed (11: Resource temporarily unavailable)"**
→ PHP-FPM is out of workers. Tune `pm.max_children` upward, or restart:

```bash
sudo systemctl restart php8.3-fpm
```

**"connect() failed (111: Connection refused) while connecting to upstream, ... 127.0.0.1:8080"**
→ Apache is down. Start it:

```bash
sudo systemctl status apache2
sudo systemctl restart apache2
```

**"upstream timed out (110: Connection timed out)"**
→ PHP script is slow. Check PHP slow log:

```bash
sudo tail -50 /var/log/php8.3-fpm.log
sudo grep slowlog /etc/php/8.3/fpm/pool.d/www.conf
```

Raise `fastcgi_read_timeout` in the Nginx location block (temporary
workaround) or fix the slow script (real fix).

**"upstream sent too big header"**
→ Session cookie or header grew beyond buffer. Raise `proxy_buffers` /
`fastcgi_buffers` in Nginx.

### Full recovery sequence

```bash
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl restart php8.3-fpm
sudo systemctl restart apache2
curl -sI https://<domain>                           # expect 200
```

---

## Branch 6: Site is slow

### Symptoms
- TTFB > 1 second.
- Complaints of slowness but site is up.
- CPU, memory, disk all look OK.

### Diagnostic sequence

```bash
# End-to-end timing
curl -w "DNS:%{time_namelookup}  Connect:%{time_connect}  SSL:%{time_appconnect}  TTFB:%{time_starttransfer}  Total:%{time_total}\n" \
    -o /dev/null -s https://<domain>

# Server health
uptime && free -h && df -h

# Are all PHP-FPM workers busy?
ps aux | grep -c "php-fpm: pool"
sudo grep pm.max_children /etc/php/8.3/fpm/pool.d/www.conf

# Is MySQL under load?
mysqladmin -u root status 2>/dev/null
mysql -e "SHOW PROCESSLIST;" 2>/dev/null
mysql -e "SHOW ENGINE INNODB STATUS\G" 2>/dev/null | head -50

# Top IPs in the access log (scraper/attack?)
sudo awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -20

# Bot signatures in user agents
sudo awk -F'"' '{print $6}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -10
```

### Common causes

1. **Slow MySQL query** — enable the slow query log, review the top offender.
2. **PHP-FPM workers exhausted** — high connection queue. Raise
   `pm.max_children` if RAM permits.
3. **External API call blocking** — the app is waiting on something upstream.
4. **Image or asset cache miss** — serve static from Nginx directly, not PHP.
5. **Scraper flood** — add rate limiting (Nginx `limit_req_zone`) or fail2ban
   jail on repeated 403/404 from one IP.

### Enabling MySQL slow query log (diagnostic)

```sql
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL slow_query_log_file = '/var/log/mysql/mysql-slow.log';
SET GLOBAL long_query_time = 1;
```

Then:

```bash
sudo tail -f /var/log/mysql/mysql-slow.log
sudo mysqldumpslow -s t /var/log/mysql/mysql-slow.log | head -20
```

---

## Branch 7: MySQL problems

### Symptoms
- Application throws DB connection errors.
- `systemctl status mysql` shows `failed` or restart loops.
- Slow queries pile up in the process list.

### Diagnostic sequence

```bash
sudo systemctl status mysql --no-pager
sudo journalctl -u mysql --since "1 hour ago" --no-pager | tail -50
sudo tail -50 /var/log/mysql/error.log
ss -tlnp | grep 3306                                # is it listening?
df -h /var/lib/mysql                                # disk space for data directory
mysql -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null
mysql -e "SHOW STATUS LIKE 'Max_used_connections';" 2>/dev/null
```

### Common causes

1. **Disk full** (`/var/lib/mysql`) — Branch 3.
2. **Too many connections** — raise `max_connections` in `mysqld.cnf`, but
   also investigate why app isn't closing connections.
3. **InnoDB corruption after a hard power loss** — needs `innodb_force_recovery`
   in `mysqld.cnf`, start, dump tables, drop, reimport.
4. **Crash after a bad config change** — revert the change.
5. **Backup running and holding locks** — check time overlap with backup cron.

### Recovery

```bash
# After fixing the cause:
sudo systemctl restart mysql
sudo systemctl status mysql --no-pager

# Reset connections if the pool is stuck:
mysql -e "SHOW PROCESSLIST;" 2>/dev/null | awk '/Sleep/{print "KILL "$1";"}' | \
    mysql 2>/dev/null

# If MySQL won't start, last-resort recovery mode (data-only, read-only):
# Edit /etc/mysql/mysql.conf.d/mysqld.cnf:
#   [mysqld]
#   innodb_force_recovery = 1
# Start, mysqldump everything, stop, remove the line, clean install, restore.
```

---

## Branch 8: SSL expired or renewal failed

### Symptoms
- Browser shows a security warning.
- `curl` fails with "certificate has expired".
- `certbot renew` emits errors.

### Diagnostic sequence

```bash
sudo certbot certificates                           # all certs + expiry dates
echo | openssl s_client -servername <domain> -connect <domain>:443 2>/dev/null \
    | openssl x509 -noout -dates                    # live cert dates
sudo certbot renew --dry-run                        # test renewal without changes
sudo certbot renew --dry-run --debug 2>&1 | tail -30
sudo journalctl -u certbot --no-pager | tail -30
sudo systemctl status certbot.timer                 # auto-renewal timer
```

### Common causes

1. **ACME HTTP-01 challenge path missing from Nginx vhost.** Every
   HTTP server block needs:
   ```nginx
   location /.well-known/acme-challenge/ { root /var/www/html; }
   ```
   Verify:
   ```bash
   sudo grep -rl "acme-challenge" /etc/nginx/sites-enabled/
   curl http://<domain>/.well-known/acme-challenge/test
   # Expect 404, not "connection refused" or 301 to https.
   ```
2. **Port 80 blocked by firewall** at the VPS level. Let's Encrypt must
   reach your server on port 80.
3. **Rate limit hit** (5 cert requests per domain per week). Wait or use
   the staging environment.
4. **DNS changed, old cert is for the old hostname**. Reissue.

### Fix and verify

```bash
sudo certbot renew --force-renewal
sudo systemctl reload nginx
curl -sI https://<domain> | grep -i "Server\|HTTP"
echo | openssl s_client -servername <domain> -connect <domain>:443 2>/dev/null \
    | openssl x509 -noout -dates
```

---

## Branch 9: Backup failed

### Symptoms
- Morning email says "backup failed" or the email is missing entirely.
- `~/backups/mysql/cron.log` shows errors.
- Google Drive is missing yesterday's file.

### Diagnostic sequence

```bash
# Did the script run?
tail -100 ~/backups/mysql/cron.log
ls -lth ~/backups/mysql/ | head -5                  # recent local files

# Did it get encrypted?
file ~/backups/mysql/mysql-backup_*.gpg | tail -5   # should say "GPG symmetrically encrypted"

# Did it upload?
rclone ls gdrive:<backup-folder> 2>&1 | tail -10
rclone about gdrive: 2>&1                           # remote reachable?

# GPG key present?
ls -la ~/.backup-encryption-key                     # must be mode 600
cat ~/.backup-encryption-key | head -c 40           # not empty?

# MySQL creds present?
ls -la ~/.mysql-backup.cnf
```

### Common failures

**"rclone: config file not found"**
→ rclone was upgraded and moved config. Check `rclone config file`.

**"rclone: The user's Drive token has expired"**
→ Re-auth:
```bash
rclone config reconnect gdrive:
```

**"mysqldump: Got error 1045: Access denied"**
→ Creds file wrong or MySQL user's password changed. Update `~/.mysql-backup.cnf`.

**"gpg: no valid OpenPGP data found"**
→ Passphrase file empty or wrong mode. Fix:
```bash
chmod 600 ~/.backup-encryption-key
ls -la ~/.backup-encryption-key
```

**"No space left on device"**
→ Branch 3. Clean up, then:
```bash
~/mysql-backup.sh     # manual re-run
```

---

## Branch 10: Site down after update-all-repos

### Symptoms
- Site was fine before the most recent `update-all-repos`.
- Now Nginx returns 500/502 or the page is blank.

### Diagnostic sequence

```bash
sudo systemctl status nginx
sudo nginx -t                                       # config broken by update?
sudo tail -30 /var/log/nginx/error.log

cd /var/www[/html]/<folder>
sudo git log --oneline -10                          # recent commits
sudo git status                                     # any leftover state?

# For Astro sites:
ls -la dist/                                        # did build run?
ls -la node_modules/                                # deps installed?

# For PHP apps:
ls -la vendor/                                      # composer installed?
sudo -u www-data php artisan about 2>/dev/null      # Laravel health
```

### Common causes

1. **Build step failed silently** — `update-all-repos` reports but the site
   uses old code.
2. **`.env` was reset** — `git reset --hard` can remove local-only files the
   repo tracks as "should exist."
3. **Database migration needed** — new code, old schema.
4. **File permissions reset** — new files owned by root, not www-data.
5. **Nginx config changed in the repo** — but the server's `sites-enabled`
   symlink points at the old copy.

### Recovery

```bash
# Roll back to the previous commit
cd /var/www[/html]/<folder>
sudo git log --oneline -5
sudo git reset --hard <previous-good-hash>

# Re-run post-commands by hand
sudo npm install --production && sudo npm run build    # Astro
sudo composer install --no-dev                         # PHP

# Fix permissions
sudo chown -R www-data:www-data /var/www/html/<folder>

# Reload web server
sudo nginx -t && sudo systemctl reload nginx
```

Long-term: fix the root cause (build script, migration, permissions) and
push a new commit rather than leaving the rollback in place.

---

## Branch 11: Can't reach the server

### Symptoms
- SSH from your laptop hangs or is refused.
- HTTPS doesn't respond.
- Only noticeable because a monitoring probe fires.

### Diagnostic sequence from the outside

```bash
# From another host or your laptop:
ping -c 3 <server-ip>                               # network reachable?
mtr -c 10 --report <server-ip>                      # where does it stop?
nc -zv <server-ip> 22                               # SSH port reachable?
nc -zv <server-ip> 443                              # HTTPS port reachable?
curl -v https://<domain> 2>&1 | head -20
```

If you can still reach *some* ports but not others:

- Can ping but can't SSH → `sshd` is down or UFW is blocking 22.
- Can SSH but can't HTTPS → Nginx is down, UFW on 443, or cert is bad.
- Can nothing → network issue at the VPS provider, or fail2ban banned you.

If you have a VPS console (serial, KVM, Hetzner web console, DigitalOcean
console):

```bash
# On the server via console:
ip -c addr                                          # interface up, address present?
ip -c route                                         # default gateway there?
ping -c 3 8.8.8.8                                   # outbound works?
ping -c 3 $(ip route | awk '/default/{print $3}')   # gateway reachable?
sudo systemctl status ssh nginx
sudo ufw status verbose
sudo fail2ban-client status sshd                    # did fail2ban ban me?
```

### Common causes

1. **`fail2ban` banned your home IP** after too many SSH attempts. Unban:
   ```bash
   sudo fail2ban-client set sshd unbanip <your-ip>
   ```
2. **`ufw` rule tightened too aggressively** by a recent change. Reset or
   add your IP:
   ```bash
   sudo ufw allow from <your-ip> to any port 22
   ```
3. **`sshd` config broke** (e.g. `Match` stanza mistake). Edit and restart
   via the console.
4. **VPS provider outage** — check their status page.
5. **DNS change in progress** — hostname no longer points at the IP you
   expect.

---

## Branch 12: Strace / process tracing

Use when a service runs but behaves wrong, or a script dies without
explaining why.

### Basic traces

```bash
# Trace all syscalls of a command (very noisy)
strace <cmd>

# Summary table of syscalls (which are slow, which fail)
strace -c -f <cmd>

# Only file-related syscalls
strace -e trace=file <cmd>

# Only network syscalls
strace -e trace=network <cmd>

# Attach to a running process by PID
sudo strace -p <pid>

# Follow child processes too
strace -f <cmd>
```

### Tracing a misbehaving service

```bash
# Find the PID
pidof nginx
ps aux | grep php-fpm | grep master

# Attach
sudo strace -f -p <master-pid> 2>&1 | tee /tmp/strace.log

# Let it run 10 seconds, Ctrl-C, then:
sudo less /tmp/strace.log
```

Look for:
- `openat(..., O_RDONLY) = -1 ENOENT` → missing file.
- `connect(..., ...) = -1 ECONNREFUSED` → can't reach another service.
- `read(..., 0)` stuck → blocked on I/O.

### Alternatives

- `ltrace` traces library calls (slower, but reveals application-level bugs).
- `perf trace` is the modern replacement, lower overhead.
- `bpftrace` for custom eBPF probes on production (lowest overhead).

---

## Branch 13: Security audit — who touched what

When you need to know *who* modified a file or *when* a change happened.

### Install auditd

```bash
sudo apt install auditd audispd-plugins
sudo systemctl enable --now auditd
```

### Add persistent rules

```bash
sudo tee /etc/audit/rules.d/linux-skills.rules > /dev/null <<'EOF'
# Account / auth changes
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# SSH config
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/ssh/sshd_config.d/ -p wa -k sshd_config

# Web root writes (catches compromise)
-w /var/www/html -p wa -k webroot
-w /etc/nginx -p wa -k nginx_config
-w /etc/apache2 -p wa -k apache_config

# Time and kernel modules
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change
-w /sbin/insmod -p x -k modules
-w /sbin/modprobe -p x -k modules

# Make rules immutable (requires reboot to change)
-e 2
EOF

sudo systemctl restart auditd
sudo auditctl -l                                    # verify loaded
```

### Searching the audit log

```bash
# Who wrote to /etc/passwd?
sudo ausearch -k identity -i | less

# All changes to sshd_config in the last day
sudo ausearch -k sshd_config --start today -i

# All failed logins
sudo aureport -au --failed

# Summary report
sudo aureport --summary

# A specific event by timestamp
sudo ausearch --start "04/10/2026 14:00:00" --end "04/10/2026 14:30:00" -i
```

### Reading the output

Key fields:
- `uid=` / `auid=` — which user.
- `comm=` — which command.
- `exe=` — which binary.
- `key=` — the tag you assigned in the rule.
- `success=yes/no` — did the syscall succeed?

Cross-reference with `/var/log/auth.log` for SSH login attribution.

---

## Sources

- Book: *Linux Command Line and Shell Scripting Bible* — process management
  and system monitoring chapters.
- Book: *Wicked Cool Shell Scripts* — diagnostic and log-analysis recipes.
- Book: *Mastering Ubuntu* (Atef, 2023) — systemd, journald, and incident
  response chapters.
- Book: *Ubuntu Server Guide* (Canonical) — service recovery and auditd.
- Man pages: `systemctl(1)`, `journalctl(1)`, `strace(1)`, `auditctl(8)`,
  `ausearch(8)`, `aureport(8)`, `ss(8)`, `iotop(8)`, `iostat(1)`.
