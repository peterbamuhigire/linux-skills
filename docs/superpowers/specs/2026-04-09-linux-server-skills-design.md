# Linux Server Skills — Design Spec

**Date:** 2026-04-09
**Author:** Peter Bamuhigire
**Status:** Approved

---

## 1. Overview

A set of 15 Claude Code skills (1 hub + 14 spokes) for managing production Linux servers.
Heavy emphasis on security and system administration. Skills are interactive-first, with
reference-style output for monitoring and log analysis tasks.

**Portability:** All skills are written for any Ubuntu/Debian server. The server context
block in Section 2 is a default profile for the primary server — when working on a
different server, the context is updated and all skills adapt automatically. No skill
hardcodes product names, app paths, or assumptions about what is currently hosted.

Skills live in: `C:\Users\Peter\.claude\skills\`

---

## 2. Server Context

Both skills are pre-loaded with this environment:

```
OS:        Ubuntu 24.04 LTS | Linux 6.8.0 | x86_64
Hostname:  server-techguypeter
Resources: 7.8GB RAM | 137GB disk (17% used) | No swap
Admin:     administrator @ /home/administrator/

Web stack:
  Nginx 1.24.0     — front-facing reverse proxy (ports 80/443)
  Apache 2.4.58    — backend for legacy PHP apps (port 8080)
  php8.3-fpm       — FastCGI PHP processor (unix socket)
  Node.js services — systemd-managed APIs (e.g. port 3001, 3002…)

Databases:
  MySQL 8.0.45     — primary database (11 production DBs)
  PostgreSQL 15    — secondary database

Security:
  UFW              — active, allows 22/80/443 only
  fail2ban         — 11 jails (sshd, apache-auth, apache-badbots,
                     apache-noscript, apache-overflows, php-url-fopen,
                     recidive, wordpress-hard, wordpress-xmlrpc, saas-api-limit)
  SSH              — keys-only (password auth disabled March 2026)
  Certbot 2.9.0    — ECDSA certs, --nginx plugin, auto-renewal via
                     certbot.timer + /etc/cron.d/certbot fallback

SSL params:        /etc/nginx/snippets/ssl-params.conf
                   TLSv1.2/1.3, HSTS 2yr, security headers, 10MB session cache

Backups:
  MySQL            — cron 8x/day → backup-alert.sh → mysql-backup.sh
                     GPG AES256 encrypted → rclone → gdrive:cloudclusters-techguy-backups
                     Local: 7 days | Google Drive: 3 days
  App files        — root cron (schedule per app) → product-specific backup script
                     GPG encrypted → Google Drive, 7-day retention
  Credentials:     ~/.mysql-backup.cnf, ~/.backup-encryption-key,
                   ~/.config/rclone/rclone.conf (all mode 600)

Deployment:
  /usr/local/bin/update-all-repos  — 15 repos, interactive menu
  /usr/local/bin/update-repos      — 3-line wrapper alias
  Warning: uses git reset --hard + git clean -fd (destroys local changes)

Nginx config:
  Main:     /etc/nginx/nginx.conf
  Sites:    /etc/nginx/sites-available/*.conf (21 files)
  Snippets: ssl-params.conf, proxy-to-apache.conf, static-files.conf,
            fastcgi-php.conf, security-dotfiles.conf
  Default:  00-default.conf returns 444 for unknown hostnames

Services (10):
  nginx, apache2, mysql, postgresql, php8.3-fpm, [Node.js services],
  fail2ban, certbot.timer, cron, msmtp
```

---

## 3. Site Deployment Patterns

The server hosts 20+ sites and apps. Projects come and go — some are transferred to
client servers, some are retired. Skills must work for any site, not specific ones.

Three deployment patterns are supported:

| Pattern | Description | Web Root Convention | Build Step |
|---|---|---|---|
| A — Astro static | Nginx serves built files directly | `/var/www/[html/]<repo>/dist` | `npm install --production && npm run build` |
| B — PHP app | Nginx proxies to Apache on port 8080 | `/var/www/html/<repo>[/public]` | none |
| C — Astro + PHP | Static front-end + PHP backend | `/var/www/html/<repo>/dist` | `composer install --no-dev && npm install --production && npm run build` |

Special cases also on the server:
- **phpMyAdmin** — Apache-served, `/usr/share/phpmyadmin`, IP-restricted
- **Node.js APIs** — systemd services, proxied by Nginx to a local port
- **WordPress sites** — PHP app (Pattern B) with specific fail2ban jails

---

## 4. Skill Map

### Hub

| Skill | Behaviour |
|---|---|
| `linux-sysadmin` | Numbered menu → routes to the correct spoke |

### Spokes (14)

| Skill | Purpose | Style |
|---|---|---|
| `linux-server-provisioning` | Fresh Ubuntu/Debian server setup A→Z | Interactive step-by-step |
| `linux-server-hardening` | Apply hardening fixes interactively | Interactive checklist |
| `linux-security-analysis` | Deep security audit — finds issues, rates severity, produces report | Analysis + report |
| `linux-access-control` | Users, SSH keys, sudo, file permissions | Interactive + reference |
| `linux-firewall-ssl` | UFW management + certbot/Let's Encrypt | Interactive |
| `linux-intrusion-detection` | fail2ban, AIDE, auditd setup & management | Interactive |
| `linux-service-management` | systemd: manage services, journalctl | Interactive + reference |
| `linux-disk-storage` | Space analysis, cleanup, swap management | Interactive |
| `linux-system-monitoring` | CPU, RAM, disk, network health reading | Reference-heavy |
| `linux-webstack` | Nginx + Apache + PHP-FPM + Node.js management | Mixed |
| `linux-log-management` | journalctl, web server/fail2ban logs, logrotate | Reference-heavy |
| `linux-troubleshooting` | Incident diagnosis: high load, OOM, crash, 502 | Interactive |
| `linux-disaster-recovery` | GPG backup decryption + restore + emergency | Interactive step-by-step |
| `linux-site-deployment` | Add new website: clone → build → Nginx → SSL → register | Interactive |

---

## 5. Per-Skill Content

### 5.1 `linux-sysadmin` (Hub)

Opens with a numbered menu:

```
What do you need to do?
  1. Set up a new server
  2. Security analysis (deep audit — findings & severity report)
  3. Security hardening (apply fixes)
  4. Manage users & access
  5. Firewall & SSL certificates
  6. Intrusion detection (fail2ban, AIDE)
  7. Manage services (nginx, mysql, php-fpm…)
  8. Disk & storage
  9. Monitor system health
 10. Web stack management (Nginx, Apache, PHP-FPM)
 11. Log management
 12. Troubleshoot an issue
 13. Disaster recovery & restore from backup
 14. Deploy a new website
```

Embeds full server context block. Routes to the corresponding spoke skill.

### 5.2 `linux-server-provisioning`

Initial Ubuntu 24.04 setup for this server pattern:

- Hostname, timezone (Africa/Nairobi), locale
- Create `administrator` user, add to sudo
- SSH: copy public key, disable password auth, harden sshd_config
- UFW baseline (22/80/443)
- Install stack: Nginx, Apache (port 8080), php8.3-fpm, MySQL 8, PostgreSQL 15,
  Redis, Node.js + PM2, fail2ban, certbot (nginx + apache plugins), rclone, msmtp
- Clone linux-skills repo to `/home/administrator/linux-skills`
- Symlink `check-server-security` and `update-all-repos`
- Configure msmtp for email alerts
- Run `check-server-security` as final verification

### 5.3 `linux-server-hardening`

- Runs `sudo check-server-security` first, reviews FAIL/WARN output
- Walks through each issue interactively, asks before applying any change
- Covers: SSH config (keys-only, PermitRootLogin no, MaxAuthTries 3),
  UFW policy review, fail2ban jail config, kernel sysctl hardening,
  Nginx `server_tokens off` + dotfile blocking, PHP-FPM security,
  MySQL bind-address, phpMyAdmin IP restriction, file permissions audit,
  GPG backup credential permissions (mode 600 check)
- Confirms current baseline is still in place (won't re-harden what's done)
- References: `notes/server-security.md`, `scripts/server-audit.sh`

### 5.4 `linux-security-analysis`

A thorough, read-only security audit that produces a severity-rated report.
**No changes are made** — this skill only observes and reports. Use
`linux-server-hardening` to fix the findings.

**Scope — 10 analysis layers:**

1. **System & kernel**
   - Kernel version + CVE exposure check
   - ASLR, dmesg_restrict, kptr_restrict, sysctl hardening parameters
   - Unattended upgrades status, pending security updates

2. **Users & authentication**
   - Accounts with UID 0 (should be root only)
   - Accounts with empty passwords
   - sudo group members — who has privilege escalation?
   - SSH config: PermitRootLogin, PasswordAuthentication, MaxAuthTries, X11Forwarding
   - Authorized keys audit across all user accounts
   - PAM password policy

3. **Network exposure**
   - All listening ports: `ss -tulnp` — what is exposed and to where?
   - Services bound to 0.0.0.0 vs 127.0.0.1 (databases must be localhost-only)
   - UFW status and rule review
   - IPv6 exposure

4. **Firewall & access control**
   - UFW default policies (incoming deny, outgoing allow)
   - Open ports vs what should be open (22, 80, 443 only for web servers)
   - Rate limiting in place?

5. **Web server security**
   - Nginx: `server_tokens`, security headers on all vhosts, dotfile blocking,
     catch-all returning 444, HSTS configuration
   - Apache: ServerTokens, ServerSignature, directory listing disabled
   - SSL/TLS: protocol versions (TLSv1.0/1.1 must be absent), cipher suites,
     HSTS, certificate expiry, ECDSA vs RSA
   - PHP-FPM: `expose_php`, `display_errors`, `allow_url_include`,
     session hardening, `disable_functions`

6. **Database security**
   - MySQL: bind-address (must be 127.0.0.1), anonymous users, test databases,
     root remote login, application user privileges (principle of least privilege)
   - PostgreSQL: listen_addresses, pg_hba.conf review
   - Redis: bind address, requirepass set, dangerous commands renamed/disabled

7. **File system**
   - World-writable files in `/var/www` and system directories
   - SUID/SGID binaries: `find / -perm /6000 -type f` — expected vs unexpected
   - Credential file permissions: all sensitive files must be mode 600
   - Unowned files: `find / -nouser -nogroup`
   - `/tmp` and `/var/tmp` sticky bit

8. **Intrusion detection & monitoring**
   - fail2ban: running, jail count, recent bans
   - AIDE: installed and database initialised?
   - auditd: running, watch rules configured?
   - Log monitoring tool present (logwatch/logcheck)?

9. **Backup integrity**
   - Backup cron jobs present and scheduled correctly
   - Last backup timestamp — is it recent?
   - Backup credential files exist and are mode 600
   - rclone remote accessible: `rclone about gdrive:`
   - GPG encryption key present

10. **Package & software**
    - Packages with available security updates
    - Installed but unnecessary services running
    - Lynis scan (if installed): `sudo lynis audit system`

**Output format — severity-rated report:**

```
SECURITY ANALYSIS REPORT
Server: <hostname> | <OS> | <date>
═══════════════════════════════════

[CRITICAL] MySQL is listening on 0.0.0.0:3306 — exposed to internet
[HIGH]     SSH password authentication is enabled
[HIGH]     3 world-writable files found in /var/www
[MEDIUM]   AIDE not installed — no file integrity monitoring
[MEDIUM]   12 packages have pending security updates
[LOW]      X11 forwarding is enabled in SSH config
[INFO]     auditd is not running (optional)
[PASS]     UFW active, default deny incoming
[PASS]     fail2ban running with 11 jails
...

Summary: 2 CRITICAL | 3 HIGH | 4 MEDIUM | 2 LOW | 6 INFO | 18 PASS
Overall security score: 72%

Recommended next step: Run linux-server-hardening to fix CRITICAL and HIGH items.
```

**Relationship to other skills:**
- `linux-security-analysis` — finds and reports (read-only)
- `linux-server-hardening` — fixes what analysis found (makes changes)
- `scripts/server-audit.sh` in linux-skills repo — lightweight quick check;
  this skill is the deep, comprehensive version

### 5.6 `linux-access-control`

- User management: create, delete, lock accounts
- Sudo group: add/remove users, audit `sudo` group members
- SSH authorized_keys: add key, revoke key, audit all keys on server
- File permissions: audit world-writable files in `/var/www`,
  verify `/etc/shadow` (640), `/etc/passwd` (644)
- Service account isolation: verify web processes run as `www-data`

### 5.7 `linux-firewall-ssl`

**UFW:**
- View current rules: `sudo ufw status verbose`
- Add/remove rules, enable rate limiting
- Standard rule set for this server (22/80/443 only)

**SSL (certbot):**
- Issue new cert: `sudo certbot --nginx -d domain.com`
- Check all cert expiry: `sudo certbot certificates`
- Dry-run renewal test: `sudo certbot renew --dry-run`
- Force renew: `sudo certbot renew --force-renewal`
- Add domain to existing cert: `--expand -d existing.com -d new.com`
- Troubleshoot renewal failure (check `.well-known/acme-challenge/` location)
- Verify `ssl-params.conf` is included in every SSL vhost

### 5.8 `linux-intrusion-detection`

**fail2ban — all 11 jails:**
- Check status: `sudo fail2ban-client status`
- Check specific jail: `sudo fail2ban-client status sshd`
- Unban an IP: `sudo fail2ban-client set sshd unbanip X.X.X.X`
- Read ban log: `sudo tail -f /var/log/fail2ban.log`
- Add custom jail (template based on `saas-api-limit` pattern)
- Tune bantime/maxretry for existing jails

**AIDE (file integrity):**
- Install and initialise: `sudo aideinit`
- Run check: `sudo aide --check`
- Interpret report output
- Schedule daily check via cron

**auditd:**
- Install and enable
- Set watch rules (e.g. watch `/etc/passwd`, `/etc/shadow`)
- Read audit log: `sudo ausearch -f /etc/passwd`

### 5.9 `linux-service-management`

For each core service (`nginx`, `apache2`, `mysql`, `postgresql`,
`php8.3-fpm`, `fail2ban`, `certbot.timer`, `cron`, `msmtp`) and any
product-specific Node.js service registered in systemd:

- Status: `sudo systemctl status <service>`
- Start/stop/restart/reload
- Enable/disable on boot
- View logs: `sudo journalctl -u <service> -n 50 --no-pager`
- Follow live logs: `sudo journalctl -u <service> -f`

**Node.js services:** check systemd service status, restart, view logs via journalctl,
  update from git — applicable to any product-specific Node.js API on the server
**php8.3-fpm specific:** check pool status, reload pool config
**msmtp specific:** test alert email manually

Debug a crashed service:
1. `systemctl status <service>` — read exit code
2. `journalctl -u <service> --since "5 min ago"` — find the error
3. Common fixes by service

### 5.10 `linux-disk-storage`

- Check disk usage: `df -h`, `du -sh /var/www/* | sort -rh | head -20`
- Find largest files: `find / -type f -size +100M 2>/dev/null`
- Clean apt cache: `sudo apt clean && sudo apt autoremove`
- Clean old npm/node_modules: identify unused builds
- Clean old logs: `sudo journalctl --vacuum-time=14d`
- Clean old backups: verify retention scripts are running
- Check inode usage: `df -i`
- No swap on this server: explain OOM risk, when to add a swapfile

**Emergency disk space** (guided): find and clear space fast when disk is
approaching full, prioritising safe targets (caches, old logs, old backups)

### 5.11 `linux-system-monitoring`

- CPU: `htop`, `top`, load averages, per-process CPU
- Memory: free/used/cached, no swap means OOM kills are possible
- Disk I/O: `iostat -x 1 5`, identify I/O-heavy processes
- Network: `ss -tunapl` for open connections, `netstat -s` for stats
- System activity: `vmstat 1 5`
- Per-service resource: `systemctl status` + `ps aux | grep <service>`
- Backup health: verify last backup timestamp and cron is active
- Quick health one-liner: `uptime && free -h && df -h && ss -tlnp`

### 5.12 `linux-webstack`

**Nginx:**
- Test config: `sudo nginx -t`
- Reload: `sudo systemctl reload nginx`
- Add/edit/disable site configs in `/etc/nginx/sites-available/`
- Read logs: `/var/log/nginx/access.log`, `/var/log/nginx/error.log`
- Debug 502/504: check if upstream (Apache/PHP-FPM/Node.js) is running
- Tune worker processes and connections in `nginx.conf`

**Apache (port 8080):**
- Manage vhosts in `/etc/apache2/sites-available/`
- Test config: `sudo apache2ctl configtest`
- Reload: `sudo systemctl reload apache2`

**PHP-FPM:**
- Check pool status
- Tune `pm.max_children` for pool
- Restart: `sudo systemctl restart php8.3-fpm`
- Read error log: `sudo tail -f /var/log/php8.3-fpm.log`

**Node.js services (product-specific, any):**
- Check service: `sudo systemctl status <service-name>`
- View logs: `sudo journalctl -u <service-name> -n 50`
- Restart after update: `sudo systemctl restart <service-name>`
- Register new Node.js service as a systemd unit (template provided)

### 5.13 `linux-log-management`

- journalctl: filter by service, time range, priority level
- Nginx logs: access pattern analysis, find 4xx/5xx spikes
- Apache logs: `/var/log/apache2/`
- fail2ban log: `/var/log/fail2ban.log` — read ban events
- MySQL slow query log: enable, read, interpret
- PHP error log: `/var/log/php8.3-fpm.log`
- Backup cron log: `~/backups/mysql/cron.log`, `/backups/dms/cron.log`
- logrotate: check config `/etc/logrotate.d/`, force rotate, add new log
- Finding attack patterns: high 404 rates, auth failure spikes, bot activity

### 5.14 `linux-troubleshooting`

Systematic diagnosis tree — asks symptoms first, then guides:

| Symptom | Diagnosis path |
|---|---|
| High CPU / load | `htop` → identify process → service-specific fix |
| High memory / OOM | `free -h` → `dmesg \| grep -i oom` → identify killed process |
| Disk full | `df -h` → `du` sweep → emergency cleanup |
| Service crashed | `systemctl status` → `journalctl` → fix + restart |
| 502/504 from Nginx | Check upstream: FPM/Apache/Node.js status + logs |
| Slow site | CPU/IO/DB query analysis |
| MySQL issues | Connection count, slow queries, disk space |
| SSL expired | `certbot certificates` → force renew |
| Backup failed | Check cron log → check rclone token → check GPG key |
| Site down after update | `nginx -t` → check update-all-repos build log |

### 5.15 `linux-disaster-recovery`

**MySQL restore (from GPG-encrypted backup):**

```bash
# 1. List available backups
rclone ls gdrive:cloudclusters-techguy-backups

# 2. Download
rclone copy gdrive:cloudclusters-techguy-backups/mysql-backup_TIMESTAMP.tar.gz.gpg ~/restore/

# 3. Decrypt
gpg --batch --passphrase-file ~/.backup-encryption-key \
    -d ~/restore/mysql-backup_TIMESTAMP.tar.gz.gpg \
    > ~/restore/mysql-backup_TIMESTAMP.tar.gz

# 4a. Restore single DB
tar xzf ~/restore/mysql-backup_TIMESTAMP.tar.gz -C ~/restore/
mysql -u root -p target_db < ~/restore/dump_TIMESTAMP/dbname.sql

# 4b. Full restore
mysql -u root -p < ~/restore/dump_TIMESTAMP/all-databases.sql
```

**App file restore:** product-specific backup scripts store archives in `/backups/<app>/` — same GPG decrypt + file restore pattern

**Demo/dev environment reset (git-tracked SQL dump pattern):**
- Some apps ship a git-tracked SQL dump as the source of truth for their demo DB
- A reset script drops + recreates the DB from that dump: `sudo reset-<app>-from-git`
- Always creates a timestamped safety backup in `/var/backups/<app>/` before destruction
- Requires typing `YES` — never skippable

**Emergency checklist after data loss:**
1. Don't panic — backups exist (local 7 days + Drive 3 days)
2. Identify what was lost and when
3. Pick the closest backup before the incident
4. Decrypt → restore → verify
5. Re-run `check-server-security` after recovery
6. Check all services are running: `systemctl status nginx mysql php8.3-fpm`

### 5.16 `linux-site-deployment`

Interactive — asks domain, site type, then walks through exact steps.

**Site types:**

| Pattern | Description | Build command |
|---|---|---|
| A — Astro static | Nginx serves /dist/ directly | `npm install --production && npm run build` |
| B — PHP app | Nginx → Apache port 8080 | none |
| C — Astro + PHP | Static front + PHP backend | `composer install --no-dev && npm install --production && npm run build` |

**The 8-step workflow:**

1. Clone repo to `/var/www/html/` (or `/var/www/`)
2. Build (Astro sites): run the appropriate build command
3. Create Nginx config in `/etc/nginx/sites-available/domain.com.conf`
   — skill generates the correct config template for the chosen pattern
4. Enable: `sudo ln -s /etc/nginx/sites-available/domain.com.conf /etc/nginx/sites-enabled/`
5. Test & reload: `sudo nginx -t && sudo systemctl reload nginx`
6. Get SSL: `sudo certbot --nginx -d domain.com`
7. If Apache-proxied (Pattern B/C): create Apache vhost on port 8080
8. Register in update-all-repos: `sudo nano /usr/local/bin/update-all-repos`
   — add: `"Display Name|/path/to/repo|build command"`

**Nginx config templates** (generated by the skill):

Pattern A (static):
```nginx
server {
    listen 80;
    server_name domain.com;
    root /var/www/html/repo-name/dist;
    index index.html;
    include snippets/security-dotfiles.conf;
    include snippets/static-files.conf;
    location /.well-known/acme-challenge/ { root /var/www/html; }
}
```

Pattern B (PHP via Apache):
```nginx
server {
    listen 80;
    server_name domain.com;
    include snippets/security-dotfiles.conf;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { include snippets/proxy-to-apache.conf; }
}
```

**Safety guardrails:**
- `nginx -t` is mandatory before every reload — skill refuses to skip it
- SSL step is never optional — skill flags if skipped
- update-all-repos registration is the final step — skill reminds using
  the CLAUDE.md rule: "New repo MUST be added to both update-all-repos and update-repos"

---

## 6. Shared Conventions

- All skills are generic Ubuntu/Debian — no product names, no hardcoded app paths
- Server context block (Section 2) is a default profile; skills adapt to any server
- Destructive operations (reset, restore, drop) always confirm before executing
- Skills reference existing linux-skills repo docs where relevant:
  - `linux-security-analysis` + `linux-server-hardening` → `notes/server-security.md`, `scripts/server-audit.sh`
  - `linux-disaster-recovery` → `notes/mysql-backup-setup.md`
  - `linux-site-deployment` → `notes/new-repo-checklist.md`
- All `.md` skill files follow the 500-line hard limit (skills repo standard)
- Each skill has frontmatter: `name` + `description` fields
- `linux-security-analysis` is always read-only — it never modifies the system

---

## 7. Implementation Order

Write skills in this order (most foundational first):

1. `linux-sysadmin` (hub — needed to route to everything else)
2. `linux-security-analysis` (deep audit — understand the security posture first)
3. `linux-server-hardening` (fix what analysis finds)
4. `linux-site-deployment` (most frequent daily operation)
5. `linux-service-management` (core operational skill)
6. `linux-troubleshooting` (incident response)
7. `linux-disaster-recovery` (critical safety net)
8. `linux-firewall-ssl`
9. `linux-intrusion-detection`
10. `linux-webstack`
11. `linux-access-control`
12. `linux-system-monitoring`
13. `linux-disk-storage`
14. `linux-log-management`
15. `linux-server-provisioning` (least frequent)

---

*Spec written: 2026-04-09*
*Knowledge base: C:\wamp64\www\linux-skills*
*Skills directory: C:\Users\Peter\.claude\skills*
