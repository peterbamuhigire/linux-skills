# Linux Server Skills — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create 15 Claude Code skills (1 hub + 14 spokes) for managing production Ubuntu/Debian servers.

**Architecture:** Hub skill presents a numbered menu and routes to 14 focused spoke skills. Each spoke is a self-contained SKILL.md covering one management domain. All skills are generic Ubuntu/Debian — no product-specific references. Server context block is embedded in the hub and carried into every spoke.

**Tech Stack:** Markdown, YAML frontmatter, bash/systemd/nginx/mysql/ufw commands

**Spec:** `docs/superpowers/specs/2026-04-09-linux-server-skills-design.md`

---

## File Structure

All files created in `C:\Users\Peter\.claude\skills\` (forward-slash paths used in commands):

```
linux-sysadmin/SKILL.md              ← write first (hub)
linux-security-analysis/SKILL.md
linux-server-hardening/SKILL.md
linux-site-deployment/SKILL.md
linux-service-management/SKILL.md
linux-troubleshooting/SKILL.md
linux-disaster-recovery/SKILL.md
linux-firewall-ssl/SKILL.md
linux-intrusion-detection/SKILL.md
linux-webstack/SKILL.md
linux-access-control/SKILL.md
linux-system-monitoring/SKILL.md
linux-disk-storage/SKILL.md
linux-log-management/SKILL.md
linux-server-provisioning/SKILL.md
```

**Skills repo is a git repo** — commit after each skill.

---

## Task 1: linux-sysadmin (Hub)

**Files:**
- Create: `/c/Users/Peter/.claude/skills/linux-sysadmin/SKILL.md`

- [ ] **Step 1: Create directory**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-sysadmin"
```

- [ ] **Step 2: Write SKILL.md**

```markdown
---
name: linux-sysadmin
description: Linux server management hub for Ubuntu/Debian production servers. Use for any server management task — security analysis, hardening, services, deployment, monitoring, troubleshooting, disaster recovery. Routes to the right specialist skill.
---
# Linux Server Admin Hub

## Server Context

This context applies to the primary managed server. Update when working on a
different server.

```
OS:        Ubuntu/Debian production server
Web:       Nginx (80/443) → PHP-FPM | Apache (8080) | Node.js services
DBs:       MySQL 8 | PostgreSQL 15 | Redis
Security:  UFW (22/80/443 only), fail2ban, SSH keys-only, certbot ECDSA certs
Backups:   Cron → backup-alert.sh → GPG AES256 → rclone → Google Drive
           Local: 7 days | Remote: 3 days | Credentials: mode 600
Deployment:/usr/local/bin/update-all-repos (git reset --hard + optional build)
Admin:     /home/administrator | Web: /var/www/html/ and /var/www/
Nginx cfg: /etc/nginx/sites-available/*.conf | snippets in /etc/nginx/snippets/
```

## Menu — Present This When Invoked

Ask: "What do you need to do?" then show:

```
Linux Server Management
═══════════════════════════════════════
  1.  Set up a new server (from scratch)
  2.  Security analysis  (deep read-only audit + severity report)
  3.  Security hardening (apply fixes interactively)
  4.  Manage users & access control
  5.  Firewall & SSL certificates
  6.  Intrusion detection (fail2ban, AIDE, auditd)
  7.  Manage services (nginx, mysql, php-fpm, cron…)
  8.  Disk & storage management
  9.  Monitor system health
 10.  Web stack (Nginx, Apache, PHP-FPM, Node.js)
 11.  Log management & analysis
 12.  Troubleshoot an issue
 13.  Disaster recovery & restore from backup
 14.  Deploy a new website
═══════════════════════════════════════
```

## Routing Table

| Choice | Invoke skill |
|--------|-------------|
| 1 | linux-server-provisioning |
| 2 | linux-security-analysis |
| 3 | linux-server-hardening |
| 4 | linux-access-control |
| 5 | linux-firewall-ssl |
| 6 | linux-intrusion-detection |
| 7 | linux-service-management |
| 8 | linux-disk-storage |
| 9 | linux-system-monitoring |
| 10 | linux-webstack |
| 11 | linux-log-management |
| 12 | linux-troubleshooting |
| 13 | linux-disaster-recovery |
| 14 | linux-site-deployment |

## Standing Rules (Apply Across All Skills)

- All skills work on any Ubuntu/Debian server — no product names in guidance
- Confirm before every destructive operation (restore, drop, reset, delete)
- Run `sudo nginx -t` before every Nginx reload — never skip this check
- Every new repo added to server MUST be registered in `/usr/local/bin/update-all-repos`
- `update-all-repos` uses `git reset --hard` — local changes are destroyed on pull
- Backup credential files must always be mode 600: check with `stat -c "%a %n" <file>`
```

- [ ] **Step 3: Verify**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-sysadmin/SKILL.md"
# Must be ≤ 500 lines
```

Confirm: frontmatter has `name` + `description`, all 14 options in menu, routing table complete, server context block present, standing rules listed.

- [ ] **Step 4: Commit**

```bash
cd "/c/Users/Peter/.claude/skills"
git add linux-sysadmin/SKILL.md
git commit -m "feat: add linux-sysadmin hub skill"
```

---

## Task 2: linux-security-analysis

**Files:**
- Create: `/c/Users/Peter/.claude/skills/linux-security-analysis/SKILL.md`

- [ ] **Step 1: Create directory**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-security-analysis"
```

- [ ] **Step 2: Write SKILL.md**

```markdown
---
name: linux-security-analysis
description: Deep read-only security audit for Ubuntu/Debian servers. Runs 10-layer analysis (kernel, users, network, firewall, web server, databases, filesystem, IDS, backups, packages) and produces a CRITICAL/HIGH/MEDIUM/LOW severity report. Never modifies the system — use linux-server-hardening to fix findings.
---
# Linux Security Analysis

**Read-only audit.** This skill observes and reports — it never modifies anything.
Use `linux-server-hardening` to fix what this skill finds.

Work through all 10 layers. For each finding output:
`[SEVERITY] Finding description`
Levels: **CRITICAL** | **HIGH** | **MEDIUM** | **LOW** | **INFO** | **PASS**

---

## Layer 1: System & Kernel

```bash
uname -r                                           # kernel version
sysctl kernel.randomize_va_space                   # ASLR — expect 2
sysctl kernel.dmesg_restrict                       # expect 1
sysctl kernel.kptr_restrict                        # expect 2
sysctl net.ipv4.tcp_syncookies                     # expect 1
sysctl net.ipv4.conf.all.accept_redirects          # expect 0
sysctl net.ipv4.conf.all.send_redirects            # expect 0
sysctl net.ipv4.conf.all.rp_filter                 # expect 1
apt list --upgradable 2>/dev/null | grep -i security | wc -l
systemctl is-enabled unattended-upgrades 2>/dev/null
```

CRITICAL if ASLR=0 | HIGH if >20 security updates pending | MEDIUM if unattended-upgrades off

## Layer 2: Users & Authentication

```bash
awk -F: '$3 == 0 {print $1}' /etc/passwd           # UID-0 accounts (only root expected)
sudo awk -F: '$2 == "" {print $1}' /etc/shadow      # empty passwords
grep ^sudo /etc/group                               # sudo members
grep -rh "^PermitRootLogin\|^PasswordAuthentication\|^MaxAuthTries\|^X11Forwarding" \
    /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null
find /home /root -name authorized_keys 2>/dev/null -exec echo "=== {} ===" \; -exec cat {} \;
```

CRITICAL if extra UID-0 accounts or empty passwords |
HIGH if PasswordAuthentication yes | HIGH if PermitRootLogin not 'no'

## Layer 3: Network Exposure

```bash
ss -tulnp                                          # all listening services
ss -tlnp | grep -E ':3306|:5432|:6379|:27017'     # databases — must be 127.0.0.1
ss -tlnp | grep ":::"                              # IPv6 listeners
```

CRITICAL if MySQL/PostgreSQL/Redis/MongoDB on 0.0.0.0 |
HIGH if unexpected ports open

## Layer 4: Firewall

```bash
sudo ufw status verbose
sudo ufw status verbose | grep "Default:"          # must be 'deny (incoming)'
```

CRITICAL if UFW inactive | HIGH if default incoming is not deny |
MEDIUM if unexpected ALLOW rules beyond 22/80/443

## Layer 5: Web Server Security

```bash
# Nginx
sudo nginx -T 2>/dev/null | grep -E "server_tokens|ssl_protocols|ssl_ciphers"
sudo nginx -T 2>/dev/null | grep -c "add_header"   # security headers count

# SSL/TLS
sudo certbot certificates 2>/dev/null              # expiry check
# Check TLSv1.0/1.1 not offered:
openssl s_client -connect localhost:443 -tls1 2>&1 | grep -E "handshake|alert"

# PHP
php -r "echo ini_get('expose_php');"               # must be empty
php -r "echo ini_get('display_errors');"           # must be empty/0
php -r "echo ini_get('allow_url_include');"        # must be empty/0
php -r "echo ini_get('session.cookie_secure');"    # must be 1
php -r "echo ini_get('disable_functions');"        # must have entries
```

CRITICAL if cert expires <7 days | HIGH if TLSv1.0/1.1 accepted |
HIGH if PHP exposes version or shows errors to users

## Layer 6: Database Security

```bash
# MySQL — bind address (must be 127.0.0.1)
grep -E "^bind-address" /etc/mysql/mysql.conf.d/mysqld.cnf \
    /etc/mysql/mariadb.conf.d/50-server.cnf 2>/dev/null

# Anonymous users and test DB
mysql -e "SELECT user,host FROM mysql.user WHERE user='';" 2>/dev/null
mysql -e "SHOW DATABASES;" 2>/dev/null | grep "^test$"

# Redis
grep -E "^bind|^requirepass|^rename-command" /etc/redis/redis.conf 2>/dev/null

# PostgreSQL
grep -v "^#\|^$" /etc/postgresql/*/main/pg_hba.conf 2>/dev/null | head -20
```

CRITICAL if databases on 0.0.0.0 | HIGH if anonymous MySQL users exist |
HIGH if Redis has no password | MEDIUM if test database exists

## Layer 7: File System

```bash
# World-writable in web root
find /var/www -type f -perm -0002 2>/dev/null

# Unexpected SUID/SGID binaries
find / -perm /6000 -type f 2>/dev/null | \
    grep -vE "(sudo|passwd|su|mount|umount|ping|crontab|at|newgrp|chsh|chfn|gpasswd)"

# Credential file permissions (must be 600)
stat -c "%a %n" ~/.mysql-backup.cnf ~/.backup-encryption-key \
    ~/.config/rclone/rclone.conf 2>/dev/null

# Critical system file permissions
stat -c "%a %n" /etc/shadow /etc/gshadow /etc/passwd /etc/ssh/sshd_config

# Unowned files
find /var/www /home /etc -nouser -nogroup 2>/dev/null | head -10
```

HIGH if world-writable files in /var/www | HIGH if credential files not 600 |
MEDIUM if unexpected SUID binaries | MEDIUM if /etc/shadow not 640

## Layer 8: Intrusion Detection & Monitoring

```bash
systemctl is-active fail2ban
sudo fail2ban-client status 2>/dev/null | grep "Number of jail"
sudo fail2ban-client status 2>/dev/null | grep "Jail list"

command -v aide >/dev/null 2>&1 && echo "AIDE installed" || echo "AIDE missing"
ls /var/lib/aide/aide.db 2>/dev/null || echo "AIDE DB not initialised"

systemctl is-active auditd 2>/dev/null

dpkg -l 2>/dev/null | grep -E "logwatch|logcheck"
```

HIGH if fail2ban not running | MEDIUM if AIDE not installed |
MEDIUM if fail2ban has <3 jails | LOW if auditd not running

## Layer 9: Backup Integrity

```bash
# Cron jobs
crontab -l 2>/dev/null | grep -iE "backup|rclone"
sudo crontab -l 2>/dev/null | grep -iE "backup|rclone"

# Last backup timestamp
ls -lt ~/backups/ 2>/dev/null | head -5
find ~/backups -name "*.gpg" -mtime -1 2>/dev/null | wc -l  # backups in last 24h

# rclone connection
rclone about gdrive: 2>/dev/null | head -2 || echo "rclone: cannot connect"

# Credential file presence
for f in ~/.mysql-backup.cnf ~/.backup-encryption-key ~/.config/rclone/rclone.conf; do
    [ -f "$f" ] && echo "EXISTS: $f" || echo "MISSING: $f"
done
```

HIGH if no backup in last 24h | HIGH if backup credentials missing |
MEDIUM if rclone cannot connect to remote | MEDIUM if no backup cron found

## Layer 10: Packages & Software

```bash
# Upgradable packages
apt list --upgradable 2>/dev/null | tail -n +2 | wc -l

# Running services not needed on a web server
systemctl list-units --type=service --state=running | \
    grep -vE "nginx|apache|mysql|postgresql|php|redis|fail2ban|ssh|cron|ufw|certbot|systemd|dbus|network"

# Lynis (if installed)
command -v lynis >/dev/null 2>&1 && \
    sudo lynis audit system --quick 2>/dev/null | grep -E "Hardening index|Warning" | head -10
```

MEDIUM if >10 upgradable packages | INFO if unexpected services running

---

## Report Output

After all 10 layers, produce this report:

```
╔══════════════════════════════════════════════════════╗
║           SECURITY ANALYSIS REPORT                  ║
╠══════════════════════════════════════════════════════╣
║ Host: <hostname>  OS: <distro>  Date: <YYYY-MM-DD>  ║
╚══════════════════════════════════════════════════════╝

[CRITICAL] <finding>
[HIGH]     <finding>
[MEDIUM]   <finding>
[LOW]      <finding>
[INFO]     <finding>
[PASS]     <finding>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 CRITICAL: X  HIGH: X  MEDIUM: X  LOW: X  PASS: X
 Security score: X%
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Recommended: Run linux-server-hardening to fix CRITICAL and HIGH items first.
```
```

- [ ] **Step 3: Verify**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-security-analysis/SKILL.md"
# Must be ≤ 500 lines
```

Confirm: all 10 layers present with actual commands, report format at end, read-only disclaimer at top, severity guidance after each layer.

- [ ] **Step 4: Commit**

```bash
cd "/c/Users/Peter/.claude/skills"
git add linux-security-analysis/SKILL.md
git commit -m "feat: add linux-security-analysis skill (10-layer audit)"
```

---

## Task 3: linux-server-hardening

**Files:**
- Create: `/c/Users/Peter/.claude/skills/linux-server-hardening/SKILL.md`

- [ ] **Step 1: Create directory**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-server-hardening"
```

- [ ] **Step 2: Write SKILL.md**

```markdown
---
name: linux-server-hardening
description: Interactive security hardening for Ubuntu/Debian servers. Runs the audit script first, then walks through each FAIL and WARN item — asks before applying any change. Covers SSH, UFW, fail2ban, kernel sysctl, Nginx, PHP-FPM, MySQL, Redis, file permissions, and backup credential security.
---
# Linux Server Hardening

Applies security fixes interactively. Always runs the audit first to understand
what needs fixing. Never applies a change without confirmation.

**Run security analysis first** (`linux-security-analysis`) if you want a full
picture before hardening. This skill focuses on fixing — ask before each change.

---

## Step 1: Run The Audit

```bash
sudo check-server-security
# If not symlinked:
sudo bash ~/linux-skills/scripts/server-audit.sh
```

Review all FAIL items first, then WARN. Work through them in order below.

---

## SSH Hardening

Create a drop-in config (survives package upgrades):

```bash
sudo nano /etc/ssh/sshd_config.d/99-hardening.conf
```

```
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 3
AllowAgentForwarding no
```

**WARNING: Keep existing SSH session open. Open a second terminal and verify
login works before closing the first.**

```bash
sudo sshd -t && sudo systemctl restart sshd
```

---

## UFW Firewall

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status verbose
```

---

## Kernel Hardening (sysctl)

```bash
sudo nano /etc/sysctl.d/99-security.conf
```

```ini
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
kernel.randomize_va_space = 2
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.sysrq = 0
```

```bash
sudo sysctl --system
```

---

## Nginx Security

```bash
# Verify these are in nginx.conf or a shared snippet:
sudo grep -r "server_tokens" /etc/nginx/
# Should show: server_tokens off;

# Verify dotfile blocking snippet is included in all vhosts:
sudo grep -r "security-dotfiles" /etc/nginx/sites-enabled/

# Verify catch-all returning 444:
sudo grep -r "444" /etc/nginx/sites-enabled/
```

Add to `/etc/nginx/nginx.conf` http block if missing:
```nginx
server_tokens off;
```

---

## PHP-FPM Security

```bash
# Find the active php.ini (Apache-loaded)
php --ini | grep "Loaded Configuration"
# Usually: /etc/php/8.x/fpm/php.ini
sudo nano /etc/php/8.3/fpm/php.ini
```

Key settings to verify/set:
```ini
expose_php = Off
display_errors = Off
log_errors = On
allow_url_include = Off
session.cookie_httponly = 1
session.cookie_secure = 1
session.use_strict_mode = 1
session.cookie_samesite = Lax
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,parse_ini_file,show_source
```

```bash
sudo systemctl restart php8.3-fpm
```

---

## MySQL Security

```bash
# Bind to localhost only
sudo grep bind-address /etc/mysql/mysql.conf.d/mysqld.cnf \
    /etc/mysql/mariadb.conf.d/50-server.cnf 2>/dev/null
# Must show: bind-address = 127.0.0.1

# Verify after restart:
ss -tlnp | grep 3306   # Must show 127.0.0.1:3306 only

# Remove anonymous users and test DB (interactive):
sudo mysql_secure_installation
```

---

## Redis Security

```bash
sudo grep -E "^bind|^requirepass" /etc/redis/redis.conf

# Must have:
# bind 127.0.0.1 -::1
# requirepass <strong-password>
```

Add to `/etc/redis/redis.conf` if missing:
```
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command CONFIG ""
rename-command DEBUG ""
```

```bash
sudo systemctl restart redis
ss -tlnp | grep 6379   # Must show 127.0.0.1:6379 only
```

---

## File Permissions

```bash
# Critical system files
sudo chmod 640 /etc/shadow /etc/gshadow
sudo chmod 644 /etc/passwd /etc/group

# Backup credentials (must be 600)
chmod 600 ~/.mysql-backup.cnf ~/.backup-encryption-key
chmod 600 ~/.config/rclone/rclone.conf

# Web root — no world-writable files
sudo find /var/www -type f -perm -0002 -exec chmod o-w {} \;

# SSH
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

---

## Verify Hardening

```bash
sudo check-server-security
# Re-run audit — FAIL items should now be PASS
```

Reference: `~/linux-skills/notes/server-security.md`
```

- [ ] **Step 3: Verify**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-server-hardening/SKILL.md"
# Must be ≤ 500 lines
```

- [ ] **Step 4: Commit**

```bash
cd "/c/Users/Peter/.claude/skills"
git add linux-server-hardening/SKILL.md
git commit -m "feat: add linux-server-hardening skill"
```

---

## Task 4: linux-site-deployment

**Files:**
- Create: `/c/Users/Peter/.claude/skills/linux-site-deployment/SKILL.md`

- [ ] **Step 1: Create directory**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-site-deployment"
```

- [ ] **Step 2: Write SKILL.md**

```markdown
---
name: linux-site-deployment
description: Deploy a new website to an Ubuntu/Debian server running Nginx + Apache dual-stack. Interactive — asks domain name and site type, generates the correct Nginx config, walks the full 8-step deployment, issues SSL, and registers the repo in update-all-repos.
---
# Linux Site Deployment

Walks the complete process of adding a new website. Ask these questions first:

1. **Domain name?** (e.g. example.com)
2. **Site type?**
   - A — Astro/static (Nginx serves `/dist/` directly)
   - B — PHP app (Nginx → Apache port 8080)
   - C — Astro + PHP hybrid (static front + PHP backend)
3. **Repo URL?** (for cloning)
4. **Does this need a Node.js API service?** (separate systemd unit)

---

## The 8-Step Deployment

### Step 1: Clone The Repo

```bash
# Most sites:
cd /var/www/html
sudo git clone <repo-url> <folder-name>

# Astro sites at /var/www/ (not /html/):
cd /var/www
sudo git clone <repo-url> <folder-name>
```

### Step 2: Build (Astro/Node.js Sites Only)

```bash
cd /var/www[/html]/<folder-name>

# Pattern A — pure Astro:
sudo npm install --production && sudo npm run build

# Pattern C — Astro + PHP:
sudo composer install --no-dev && sudo npm install --production && sudo npm run build
```

### Step 3: Create Nginx Config

```bash
sudo nano /etc/nginx/sites-available/<domain>.conf
```

**Pattern A — Astro static:**
```nginx
server {
    listen 80;
    server_name <domain>;
    root /var/www[/html]/<folder>/dist;
    index index.html;
    include snippets/security-dotfiles.conf;
    include snippets/static-files.conf;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

**Pattern B — PHP app via Apache:**
```nginx
server {
    listen 80;
    server_name <domain>;
    include snippets/security-dotfiles.conf;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / {
        include snippets/proxy-to-apache.conf;
    }
}
```

**Pattern C — Astro + PHP hybrid:**
```nginx
server {
    listen 80;
    server_name <domain>;
    root /var/www/html/<folder>/dist;
    include snippets/security-dotfiles.conf;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location /api/ {
        include snippets/proxy-to-apache.conf;
    }
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

### Step 4: Enable The Site

```bash
sudo ln -s /etc/nginx/sites-available/<domain>.conf /etc/nginx/sites-enabled/
```

### Step 5: Test & Reload Nginx

```bash
sudo nginx -t
# MUST pass before continuing — fix any errors first
sudo systemctl reload nginx
```

### Step 6: Issue SSL Certificate

```bash
sudo certbot --nginx -d <domain>
# Certbot modifies the Nginx config to add SSL and HTTP→HTTPS redirect
# Verify:
sudo certbot certificates | grep -A3 "<domain>"
```

### Step 7: Apache Vhost (Pattern B and C Only)

```bash
sudo nano /etc/apache2/sites-available/<domain>.conf
```

```apache
<VirtualHost *:8080>
    ServerName <domain>
    DocumentRoot /var/www/html/<folder>[/public]
    <Directory /var/www/html/<folder>[/public]>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog ${APACHE_LOG_DIR}/<domain>-error.log
    CustomLog ${APACHE_LOG_DIR}/<domain>-access.log combined
</VirtualHost>
```

```bash
sudo a2ensite <domain>.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

### Step 8: Register in update-all-repos

**This is mandatory.** Per `~/linux-skills/notes/new-repo-checklist.md`:

```bash
sudo nano /usr/local/bin/update-all-repos
```

Add to the REPO_LIST array:
```bash
# Pattern A/B (no composer):
"Display Name|/var/www[/html]/<folder>|npm install --production && npm run build"

# Pattern B — PHP only (no build):
"Display Name|/var/www/html/<folder>|"

# Pattern C — Astro + PHP:
"Display Name|/var/www/html/<folder>|composer install --no-dev && npm install --production && npm run build"
```

**WARNING:** `update-all-repos` runs `git reset --hard + git clean -fd`.
Any uncommitted server-side changes are destroyed on next pull.
Always commit local edits to git before running it.

---

## Verify Deployment

```bash
curl -sI https://<domain> | grep -E "HTTP/|Location:|Server:"
sudo certbot certificates | grep -A4 "<domain>"
sudo nginx -t
```

---

## Node.js API Service (If Needed)

Create a systemd unit for any Node.js API:

```bash
sudo nano /etc/systemd/system/<service-name>.service
```

```ini
[Unit]
Description=<App Name> API
After=network.target

[Service]
Type=simple
User=administrator
WorkingDirectory=/var/www/html/<folder>
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=10
Environment=NODE_ENV=production PORT=3001

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable <service-name>
sudo systemctl start <service-name>
sudo systemctl status <service-name>
```
```

- [ ] **Step 3: Verify**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-site-deployment/SKILL.md"
# Must be ≤ 500 lines
```

- [ ] **Step 4: Commit**

```bash
cd "/c/Users/Peter/.claude/skills"
git add linux-site-deployment/SKILL.md
git commit -m "feat: add linux-site-deployment skill (3 patterns, 8-step workflow)"
```

---

## Task 5: linux-service-management

**Files:**
- Create: `/c/Users/Peter/.claude/skills/linux-service-management/SKILL.md`

- [ ] **Step 1: Create directory + write SKILL.md**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-service-management"
```

Write `/c/Users/Peter/.claude/skills/linux-service-management/SKILL.md`:

```markdown
---
name: linux-service-management
description: Manage systemd services on Ubuntu/Debian servers. Start, stop, restart, reload, enable/disable, view status and logs for all server services (nginx, apache2, mysql, postgresql, php-fpm, redis, fail2ban, certbot, cron, msmtp) and any product-specific Node.js services. Includes journalctl log viewing and crashed-service diagnosis.
---
# Linux Service Management

## Core Service Commands

```bash
# Check status
sudo systemctl status <service>

# Start / Stop / Restart / Reload
sudo systemctl start <service>
sudo systemctl stop <service>
sudo systemctl restart <service>
sudo systemctl reload <service>     # graceful — not all services support this

# Enable / Disable on boot
sudo systemctl enable <service>
sudo systemctl disable <service>

# Check enabled state
sudo systemctl is-enabled <service>
sudo systemctl is-active <service>
```

## Services On This Server

| Service | Restart | Reload | Notes |
|---|---|---|---|
| `nginx` | `restart` | `reload` | Test with `nginx -t` before reload |
| `apache2` | `restart` | `reload` | Test with `apache2ctl configtest` first |
| `mysql` | `restart` | — | Brief downtime expected |
| `postgresql` | `restart` | `reload` | reload re-reads postgresql.conf |
| `php8.3-fpm` | `restart` | `reload` | reload is graceful for active connections |
| `redis` | `restart` | — | |
| `fail2ban` | `restart` | `reload` | reload re-reads jail configs |
| `certbot.timer` | `restart` | — | systemd timer for cert renewal |
| `cron` | `restart` | — | |
| `msmtp` | — | — | Not a daemon; test with command below |

---

## Viewing Logs

```bash
# Last 50 lines, no pager
sudo journalctl -u <service> -n 50 --no-pager

# Follow live (Ctrl+C to stop)
sudo journalctl -u <service> -f

# Since a specific time
sudo journalctl -u <service> --since "1 hour ago"
sudo journalctl -u <service> --since "2026-04-09 10:00"

# Only errors and above
sudo journalctl -u <service> -p err --no-pager

# All services since last boot
sudo journalctl -b --no-pager | tail -100
```

---

## Diagnosing A Crashed Service

When `systemctl status <service>` shows `failed`:

```bash
# Step 1: Read the exit code and last log lines
sudo systemctl status <service> --no-pager

# Step 2: Get the full error context
sudo journalctl -u <service> --since "5 min ago" --no-pager

# Step 3: Check for config errors (web servers)
sudo nginx -t                       # nginx
sudo apache2ctl configtest          # apache2
sudo php-fpm8.3 -t                 # php-fpm

# Step 4: Check disk space (service may fail if disk full)
df -h

# Step 5: Check for port conflicts
sudo ss -tlnp | grep <port>
```

Common fixes by service:
- **nginx**: config syntax error → `nginx -t` to find it
- **mysql**: disk full, corrupt table → check `journalctl -u mysql`
- **php8.3-fpm**: bad php.ini setting → `php-fpm8.3 -t`
- **fail2ban**: bad jail config → check `/etc/fail2ban/jail.local`

---

## Service-Specific Operations

### nginx — test before reload (always)
```bash
sudo nginx -t && sudo systemctl reload nginx
```

### php8.3-fpm — check pool status
```bash
# Pool status (if status page enabled in pool config)
curl -s http://127.0.0.1/fpm-status 2>/dev/null

# Tune workers: edit pool config
sudo nano /etc/php/8.3/fpm/pool.d/www.conf
# Key settings: pm.max_children, pm.start_servers, pm.min_spare_servers
sudo systemctl reload php8.3-fpm
```

### msmtp — test alert email
```bash
echo "Subject: Test\n\nTest email from $(hostname)" | \
    msmtp --debug --account=default <your@email.com>
```

### certbot.timer — verify renewal
```bash
sudo systemctl status certbot.timer
sudo certbot renew --dry-run
```

### Node.js services (product-specific)
```bash
# Check any Node.js service registered in systemd
sudo systemctl status <service-name>
sudo journalctl -u <service-name> -n 50 --no-pager

# After updating code via update-all-repos:
sudo systemctl restart <service-name>
```

---

## Check All Services At Once

```bash
sudo systemctl list-units --type=service --state=failed
sudo systemctl list-units --type=service --state=running | \
    grep -E "nginx|apache|mysql|postgresql|php|redis|fail2ban"
```
```

- [ ] **Step 2: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-service-management/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-service-management/SKILL.md
git commit -m "feat: add linux-service-management skill"
```

---

## Task 6: linux-troubleshooting

**Files:**
- Create: `/c/Users/Peter/.claude/skills/linux-troubleshooting/SKILL.md`

- [ ] **Step 1: Create directory + write SKILL.md**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-troubleshooting"
```

Write `/c/Users/Peter/.claude/skills/linux-troubleshooting/SKILL.md`:

```markdown
---
name: linux-troubleshooting
description: Systematic incident diagnosis for Ubuntu/Debian production servers. Ask for the symptom — high load, OOM kill, disk full, service crashed, 502/504 errors, slow site, MySQL issues, SSL expired, backup failed, site down after update — then walk through the diagnosis tree step by step.
---
# Linux Troubleshooting

Ask: "What's the symptom?" then follow the matching branch below.

---

## High CPU / Load Average

```bash
uptime                              # load averages: 1m, 5m, 15m
# Load > number of CPU cores = overloaded
nproc                               # how many cores?

htop                                # identify top CPU processes (press P to sort)
# or: top -bn1 | head -20

# If a PHP-FPM worker is maxed out:
sudo systemctl status php8.3-fpm
sudo journalctl -u php8.3-fpm --since "10 min ago"

# If MySQL is the culprit:
mysql -e "SHOW PROCESSLIST;" 2>/dev/null | head -20
```

Fix paths: restart the offending service | kill runaway process (`kill -9 <pid>`) |
reduce php-fpm `pm.max_children` if RAM is the bottleneck

---

## High Memory / OOM Kill

```bash
free -h                             # used/available/cached
# No swap on server means OOM killer fires when RAM exhausted

# Check if OOM killer fired recently:
sudo dmesg | grep -i "oom\|killed process" | tail -10
sudo journalctl -k --since "1 hour ago" | grep -i oom

# Which processes use most RAM:
ps aux --sort=-%mem | head -15

# MySQL buffer pool (often biggest consumer):
mysql -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';" 2>/dev/null
```

Emergency: `sudo systemctl restart mysql` or restart the offending service
Consider adding a swapfile (`linux-disk-storage`) as an OOM safety net

---

## Disk Full

```bash
df -h                               # which filesystem is full?
du -sh /var/www/* | sort -rh | head -10
du -sh /var/log/* 2>/dev/null | sort -rh | head -10
du -sh ~/backups/* 2>/dev/null | sort -rh | head -5

# Quick wins (safe to delete):
sudo apt clean                      # apt cache
sudo journalctl --vacuum-time=14d   # old journal logs
sudo journalctl --vacuum-size=500M  # cap journal size

# Find large files:
sudo find / -type f -size +100M 2>/dev/null | grep -v proc

# Check inodes (sometimes inodes full, not space):
df -i
```

---

## Service Crashed / Won't Start

```bash
sudo systemctl status <service> --no-pager
sudo journalctl -u <service> --since "10 min ago" --no-pager

# Web servers — check config first:
sudo nginx -t
sudo apache2ctl configtest

# Port conflict:
sudo ss -tlnp | grep <port>
```

See `linux-service-management` for service-specific diagnosis steps.

---

## 502 / 504 Bad Gateway (Nginx)

```bash
# 502 = upstream not responding | 504 = upstream timeout

# Check which upstream Nginx is trying to reach:
sudo tail -20 /var/log/nginx/error.log

# Check if the upstream is running:
sudo systemctl status php8.3-fpm   # PHP sites
sudo systemctl status apache2      # PHP app sites (proxied to Apache)
sudo systemctl status <node-svc>   # Node.js API sites

# PHP-FPM socket exists?
ls -la /run/php/php8.3-fpm.sock

# Restart the failing upstream:
sudo systemctl restart php8.3-fpm
sudo systemctl restart apache2
```

---

## Slow Site

```bash
# 1. Is it slow for all sites or one?
curl -w "\nTime: %{time_total}s\n" -o /dev/null -s https://<domain>

# 2. Server load OK?
uptime && free -h

# 3. MySQL slow?
mysql -e "SHOW PROCESSLIST;" 2>/dev/null
sudo tail -20 /var/log/mysql/error.log

# 4. PHP-FPM workers exhausted?
# Check pm.max_children in /etc/php/8.3/fpm/pool.d/www.conf
ps aux | grep php-fpm | wc -l

# 5. Nginx access log — is one IP hammering the server?
sudo tail -100 /var/log/nginx/access.log | awk '{print $1}' | sort | uniq -c | sort -rn | head
```

---

## MySQL Issues

```bash
# Connection refused?
sudo systemctl status mysql
sudo journalctl -u mysql --since "10 min ago"
ss -tlnp | grep 3306

# Too many connections?
mysql -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null
mysql -e "SHOW VARIABLES LIKE 'max_connections';" 2>/dev/null

# Disk space (MySQL needs space to write):
df -h /var/lib/mysql

# Slow queries?
mysql -e "SHOW VARIABLES LIKE 'slow_query_log';" 2>/dev/null
sudo tail -20 /var/log/mysql/mysql-slow.log 2>/dev/null
```

---

## SSL Certificate Expired / Renewal Failed

```bash
sudo certbot certificates              # check all cert expiry dates

# Force renewal:
sudo certbot renew --force-renewal

# If renewal fails — check ACME challenge location is in Nginx config:
sudo grep "well-known" /etc/nginx/sites-enabled/*.conf

# Dry run to test without issuing:
sudo certbot renew --dry-run
```

---

## Backup Failed

```bash
# Check cron log
tail -50 ~/backups/mysql/cron.log

# Did the alert email fire? Check msmtp:
sudo journalctl | grep msmtp | tail -10

# Test rclone connection:
rclone about gdrive:

# GPG key present?
ls -la ~/.backup-encryption-key
cat ~/.backup-encryption-key | wc -c   # should be > 0

# Test backup manually:
~/mysql-backup.sh
```

---

## Site Down After update-all-repos

```bash
# Check if Nginx is still running:
sudo systemctl status nginx

# Check Nginx config (update may have overwritten a config file):
sudo nginx -t

# Check build log (for Astro sites):
# The build output is in the terminal from update-all-repos

# Roll back: git log to find the last good commit, then:
cd /var/www[/html]/<folder>
sudo git log --oneline -5
sudo git reset --hard <good-commit-hash>
sudo npm run build  # if Astro site
sudo systemctl reload nginx
```
```

- [ ] **Step 2: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-troubleshooting/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-troubleshooting/SKILL.md
git commit -m "feat: add linux-troubleshooting skill (8 diagnosis branches)"
```

---

## Task 7: linux-disaster-recovery

**Files:**
- Create: `/c/Users/Peter/.claude/skills/linux-disaster-recovery/SKILL.md`

- [ ] **Step 1: Create directory + write SKILL.md**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-disaster-recovery"
```

Write `/c/Users/Peter/.claude/skills/linux-disaster-recovery/SKILL.md`:

```markdown
---
name: linux-disaster-recovery
description: Restore from GPG-encrypted backups on Ubuntu/Debian servers. Covers MySQL database restore (single DB or full), app file restore, and emergency recovery checklist. Decrypts AES256 GPG archives from Google Drive via rclone. Always confirms before any destructive restore operation.
---
# Linux Disaster Recovery

**Always confirm before restoring.** A restore overwrites existing data.
Identify what was lost and when before choosing a backup to restore from.

---

## Step 1: Assess The Situation

```bash
# What services are affected?
sudo systemctl status nginx mysql postgresql php8.3-fpm

# When did the incident happen? (approximate)
sudo journalctl --since "2 hours ago" | grep -iE "error|fail|crash" | head -20

# Is there data corruption or just a service crash?
# Service crash → restart it, no restore needed
# Data corruption/loss → find the right backup, restore
```

---

## Step 2: List Available Backups

```bash
# Local backups (7-day retention)
ls -lth ~/backups/mysql/*.gpg 2>/dev/null | head -10

# Google Drive backups (3-day retention for MySQL)
rclone ls gdrive:<backup-folder> 2>/dev/null | sort -k2 | tail -10

# If rclone fails to connect:
rclone about gdrive:
rclone config reconnect gdrive:    # if token expired
```

Choose the backup **closest to before the incident**.

---

## Step 3: Download From Google Drive

```bash
mkdir -p ~/restore
rclone copy gdrive:<backup-folder>/mysql-backup_TIMESTAMP.tar.gz.gpg ~/restore/
ls -lh ~/restore/
```

---

## Step 4: Decrypt The Backup

```bash
gpg --batch \
    --passphrase-file ~/.backup-encryption-key \
    -d ~/restore/mysql-backup_TIMESTAMP.tar.gz.gpg \
    > ~/restore/mysql-backup_TIMESTAMP.tar.gz

# Verify decryption succeeded:
ls -lh ~/restore/mysql-backup_TIMESTAMP.tar.gz
```

If GPG fails (`bad passphrase` / `no secret key`):
```bash
cat ~/.backup-encryption-key          # verify key file is not empty
ls -la ~/.backup-encryption-key       # must be mode 600
```

---

## Step 5: Extract The Archive

```bash
tar xzf ~/restore/mysql-backup_TIMESTAMP.tar.gz -C ~/restore/
ls ~/restore/dump_*/                   # see what databases are available
```

---

## Step 6: Restore

### Restore A Single Database

```bash
# ⚠ CONFIRM before running — this overwrites the existing database
mysql -u root -p <database_name> < ~/restore/dump_TIMESTAMP/<database_name>.sql
```

### Restore All Databases (Full System Restore)

```bash
# ⚠ CONFIRM — this overwrites ALL databases
mysql -u root -p < ~/restore/dump_TIMESTAMP/all-databases.sql
```

### Restore Using Credentials File

```bash
mysql --defaults-file=~/.mysql-backup.cnf <db_name> < ~/restore/dump_TIMESTAMP/<db>.sql
```

---

## Step 7: Verify The Restore

```bash
mysql -e "SHOW DATABASES;" 2>/dev/null
mysql -e "SELECT COUNT(*) FROM <database>.<key_table>;" 2>/dev/null
sudo systemctl status mysql
```

---

## App File Restore

Some applications have their own backup scripts that back up files + database
(typically to `/backups/<app>/`):

```bash
# Decrypt and extract (same pattern as MySQL backups):
gpg --batch --passphrase-file ~/.backup-encryption-key \
    -d /backups/<app>/backup_TIMESTAMP.tar.gz.gpg \
    > /tmp/app-restore.tar.gz
tar xzf /tmp/app-restore.tar.gz -C /tmp/app-restore/
# Then copy files back to web root
sudo rsync -av /tmp/app-restore/<app-files>/ /var/www/html/<app>/
```

---

## Demo/Dev Environment Reset

Some apps ship a git-tracked SQL dump as source of truth for the demo database.
A reset script drops and recreates the DB from that dump:

```bash
# Find the reset script for the app:
ls /usr/local/bin/reset-*

# Run it (requires typing YES):
sudo reset-<app>-from-git

# Backup always created before destruction in /var/backups/<app>/
ls /var/backups/<app>/ | tail -5
```

---

## Emergency Checklist (After Major Data Loss)

```bash
# 1. Don't make things worse — stop the affected service
sudo systemctl stop <service>

# 2. Check both local and remote for the best backup
ls -lth ~/backups/mysql/*.gpg | head -5
rclone ls gdrive:<backup-folder> | sort | tail -5

# 3. Decrypt → restore → verify (steps 3-7 above)

# 4. Check all services are running after restore
sudo systemctl status nginx mysql php8.3-fpm

# 5. Re-run security audit (make sure restore didn't undo hardening)
sudo check-server-security

# 6. Cleanup restore files
rm -rf ~/restore/
```

---

## Cleanup After Restore

```bash
rm -rf ~/restore/
# Keep the .gpg archive if you may need to restore again
# It will be auto-deleted when the 7-day local retention runs
```
```

- [ ] **Step 2: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-disaster-recovery/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-disaster-recovery/SKILL.md
git commit -m "feat: add linux-disaster-recovery skill (GPG decrypt + restore)"
```

---

## Task 8: linux-firewall-ssl

**Files:**
- Create: `/c/Users/Peter/.claude/skills/linux-firewall-ssl/SKILL.md`

- [ ] **Step 1: Create + write**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-firewall-ssl"
```

Write `/c/Users/Peter/.claude/skills/linux-firewall-ssl/SKILL.md`:

```markdown
---
name: linux-firewall-ssl
description: Manage UFW firewall and SSL/TLS certificates on Ubuntu/Debian servers. UFW rule management (view, add, remove, rate limiting). Certbot operations (issue certs with --nginx plugin, check expiry, force renew, dry run, add domains, troubleshoot renewal). ECDSA certificates, TLSv1.2/1.3 only.
---
# Firewall & SSL Management

## UFW Firewall

### View Current Rules
```bash
sudo ufw status verbose
sudo ufw status numbered      # numbered list for easy deletion
```

### Standard Rule Set (web server)
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp         # SSH
sudo ufw allow 80/tcp         # HTTP
sudo ufw allow 443/tcp        # HTTPS
sudo ufw enable
```

### Add / Remove Rules
```bash
# Add a rule
sudo ufw allow <port>/tcp
sudo ufw allow from <ip> to any port 22     # restrict SSH to specific IP

# Remove by number
sudo ufw status numbered
sudo ufw delete <number>

# Remove by rule
sudo ufw delete allow <port>/tcp
```

### Rate Limiting (brute-force protection)
```bash
sudo ufw limit 22/tcp         # max 6 connections per 30 seconds per IP
```

### UFW Logging
```bash
sudo ufw logging on           # medium verbosity
sudo tail -f /var/log/ufw.log
```

---

## SSL Certificates (Certbot)

### Issue A New Certificate
```bash
# Nginx plugin (primary — modifies Nginx config automatically):
sudo certbot --nginx -d example.com
sudo certbot --nginx -d example.com -d www.example.com

# Apache plugin (for Apache-only vhosts):
sudo certbot --apache -d example.com
```

### Check All Certificate Expiry
```bash
sudo certbot certificates
# Lists each cert with: domains, expiry date, days remaining
```

### Test Auto-Renewal (Dry Run)
```bash
sudo certbot renew --dry-run
# Must complete without errors
```

### Force Renew A Certificate
```bash
sudo certbot renew --force-renewal
# Use when cert is approaching expiry and auto-renewal hasn't run
```

### Add A Domain To An Existing Certificate
```bash
sudo certbot --nginx --expand -d existing.com -d newdomain.com
```

### Renew A Specific Certificate
```bash
sudo certbot renew --cert-name example.com
```

### Verify Auto-Renewal Is Active
```bash
# Systemd timer (primary):
sudo systemctl status certbot.timer
sudo systemctl is-enabled certbot.timer

# Cron fallback:
cat /etc/cron.d/certbot 2>/dev/null
```

---

## SSL Parameters

The shared SSL config at `/etc/nginx/snippets/ssl-params.conf` must include:

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_stapling on;
ssl_stapling_verify on;

add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Permissions-Policy "geolocation=(), camera=(), microphone=()" always;
```

Verify it is included in every SSL vhost:
```bash
sudo grep -r "ssl-params.conf" /etc/nginx/sites-enabled/
# Every SSL vhost must include it
```

---

## Troubleshoot Renewal Failure

Renewal relies on the `.well-known/acme-challenge/` location being accessible.
Every HTTP server block must have:

```nginx
location /.well-known/acme-challenge/ {
    root /var/www/html;
}
```

Verify:
```bash
sudo grep -r "acme-challenge" /etc/nginx/sites-enabled/
# Must appear in every domain's HTTP (port 80) server block

# Test that the challenge path is reachable:
curl -s http://example.com/.well-known/acme-challenge/test
# Should return 404 (not connection refused)
```

If renewal still fails:
```bash
sudo certbot renew --dry-run --debug
sudo journalctl -u certbot --no-pager | tail -30
```
```

- [ ] **Step 2: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-firewall-ssl/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-firewall-ssl/SKILL.md
git commit -m "feat: add linux-firewall-ssl skill"
```

---

## Task 9: linux-intrusion-detection

**Files:**
- Create: `/c/Users/Peter/.claude/skills/linux-intrusion-detection/SKILL.md`

- [ ] **Step 1: Create + write**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-intrusion-detection"
```

Write `/c/Users/Peter/.claude/skills/linux-intrusion-detection/SKILL.md`:

```markdown
---
name: linux-intrusion-detection
description: Manage intrusion detection on Ubuntu/Debian servers. fail2ban (check jails, unban IPs, add custom jails, tune ban settings, read ban logs). AIDE file integrity monitoring (install, initialise, run checks, schedule). auditd system call auditing (install, set file watches, read audit log).
---
# Intrusion Detection

## fail2ban

### Check Status
```bash
sudo fail2ban-client status                        # all jails
sudo fail2ban-client status sshd                   # specific jail
sudo fail2ban-client status sshd | grep "Currently banned"
```

### Check Banned IPs
```bash
sudo fail2ban-client status <jail>                 # shows banned IPs
sudo tail -50 /var/log/fail2ban.log                # recent activity
sudo tail -f /var/log/fail2ban.log                 # live monitoring
```

### Unban an IP
```bash
sudo fail2ban-client set <jail> unbanip <ip>
# Example:
sudo fail2ban-client set sshd unbanip 192.168.1.100
```

### Standard Jail Configuration

Create/edit `/etc/fail2ban/jail.local` (never edit `jail.conf`):

```ini
[DEFAULT]
bantime  = 86400
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled  = true
port     = ssh
maxretry = 4
bantime  = 3600

[apache-auth]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/error.log
maxretry = 5
bantime  = 1800

[apache-badbots]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/access.log
bantime  = 172800

[apache-noscript]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/access.log

[recidive]
enabled  = true
logpath  = /var/log/fail2ban.log
bantime  = 604800
findtime = 86400
maxretry = 5
```

### Add A Custom Jail (e.g. for a SaaS API rate limit)

```ini
# In /etc/fail2ban/jail.local:
[saas-api-limit]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 30
findtime = 60
bantime  = 3600
filter   = saas-api-limit
```

Create the filter at `/etc/fail2ban/filter.d/saas-api-limit.conf`:
```ini
[Definition]
failregex = ^<HOST> .* "POST /api/
ignoreregex =
```

```bash
sudo systemctl reload fail2ban
sudo fail2ban-client status saas-api-limit
```

### Reload After Config Changes
```bash
sudo systemctl reload fail2ban
sudo fail2ban-client status              # verify jails loaded
```

---

## AIDE (File Integrity Monitoring)

Detects unauthorised changes to system files.

### Install
```bash
sudo apt install aide
```

### Initialise (First Time)
```bash
sudo aideinit                            # takes a few minutes, reads all files
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

### Run Integrity Check
```bash
sudo aide --check
# OUTPUT: lists any files that changed since last init
# No output = no changes detected
```

### Update Database After Legitimate Changes
```bash
sudo aideinit
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

### Schedule Daily Check
```bash
sudo nano /etc/cron.daily/aide-check
```
```bash
#!/bin/bash
aide --check | mail -s "AIDE Report $(hostname) $(date +%Y-%m-%d)" root
```
```bash
sudo chmod +x /etc/cron.daily/aide-check
```

---

## auditd (System Call Auditing)

Tracks specific file access and system calls.

### Install and Enable
```bash
sudo apt install auditd
sudo systemctl enable auditd
sudo systemctl start auditd
```

### Add Watch Rules
```bash
# Watch critical files for any access/modification:
sudo auditctl -w /etc/passwd -p rwxa -k passwd-changes
sudo auditctl -w /etc/shadow -p rwxa -k shadow-changes
sudo auditctl -w /etc/ssh/sshd_config -p rwxa -k ssh-config
sudo auditctl -w /var/www -p w -k webroot-writes

# Make rules persistent:
sudo nano /etc/audit/rules.d/hardening.rules
```
```
-w /etc/passwd -p rwxa -k passwd-changes
-w /etc/shadow -p rwxa -k shadow-changes
-w /etc/ssh/sshd_config -p rwxa -k ssh-config
-w /var/www -p w -k webroot-writes
```

### Search Audit Log
```bash
sudo ausearch -k passwd-changes         # events matching rule key
sudo ausearch -f /etc/passwd            # events for specific file
sudo ausearch --start today             # today's events
sudo aureport --summary                 # activity summary
```
```

- [ ] **Step 2: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-intrusion-detection/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-intrusion-detection/SKILL.md
git commit -m "feat: add linux-intrusion-detection skill (fail2ban, AIDE, auditd)"
```

---

## Task 10: linux-webstack

**Files:**
- Create: `/c/Users/Peter/.claude/skills/linux-webstack/SKILL.md`

- [ ] **Step 1: Create + write**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-webstack"
```

Write `/c/Users/Peter/.claude/skills/linux-webstack/SKILL.md`:

```markdown
---
name: linux-webstack
description: Manage the web stack on Ubuntu/Debian servers — Nginx reverse proxy (config, reload, 502 debug), Apache backend (port 8080 vhosts), PHP-FPM (pool tuning, restart, logs), and Node.js API services (systemd management). Covers the Nginx+Apache dual-stack pattern where Nginx fronts all traffic and proxies PHP apps to Apache.
---
# Web Stack Management

Stack overview:
```
Client → Nginx (443/80)
           ├── Astro/static sites → /dist/ folders
           ├── PHP API → PHP-FPM socket (fastcgi)
           ├── PHP apps → Apache (port 8080)
           └── Node.js APIs → localhost:<port>
```

---

## Nginx

### Test Config (Always Before Reload)
```bash
sudo nginx -t
# Must show: syntax is ok | test is successful
```

### Reload / Restart
```bash
sudo nginx -t && sudo systemctl reload nginx    # graceful — no downtime
sudo systemctl restart nginx                    # full restart — brief downtime
```

### Manage Site Configs
```bash
# Enable a site
sudo ln -s /etc/nginx/sites-available/<domain>.conf /etc/nginx/sites-enabled/

# Disable a site
sudo rm /etc/nginx/sites-enabled/<domain>.conf

# List enabled sites
ls -la /etc/nginx/sites-enabled/

# Edit a site config
sudo nano /etc/nginx/sites-available/<domain>.conf
sudo nginx -t && sudo systemctl reload nginx
```

### View Logs
```bash
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
sudo tail -100 /var/log/nginx/error.log | grep -i "error\|crit\|alert"
```

### Debug 502 Bad Gateway
```bash
# 1. What does the error log say?
sudo tail -20 /var/log/nginx/error.log

# 2. Is the upstream running?
sudo systemctl status php8.3-fpm       # for PHP-FPM sites
sudo systemctl status apache2          # for Apache-proxied sites

# 3. Does the PHP-FPM socket exist?
ls -la /run/php/php8.3-fpm.sock

# 4. Restart the upstream:
sudo systemctl restart php8.3-fpm
sudo systemctl restart apache2
```

### nginx.conf Key Settings
```bash
sudo nano /etc/nginx/nginx.conf
```
```nginx
worker_processes auto;              # matches CPU cores
worker_connections 1024;            # per worker

# In http block:
server_tokens off;                  # hide Nginx version
gzip on;
client_max_body_size 64M;           # upload limit
```

---

## Apache (Port 8080 Backend)

### Manage Vhosts
```bash
# Create
sudo nano /etc/apache2/sites-available/<domain>.conf

# Enable
sudo a2ensite <domain>.conf
sudo apache2ctl configtest && sudo systemctl reload apache2

# Disable
sudo a2dissite <domain>.conf
sudo systemctl reload apache2
```

### Test Config
```bash
sudo apache2ctl configtest
# Must show: Syntax OK
```

### Standard PHP App Vhost (Port 8080)
```apache
<VirtualHost *:8080>
    ServerName <domain>
    DocumentRoot /var/www/html/<folder>[/public]
    <Directory /var/www/html/<folder>[/public]>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog  ${APACHE_LOG_DIR}/<domain>-error.log
    CustomLog ${APACHE_LOG_DIR}/<domain>-access.log combined
</VirtualHost>
```

### View Apache Logs
```bash
sudo tail -f /var/log/apache2/error.log
sudo tail -f /var/log/apache2/access.log
```

---

## PHP-FPM

### Check Status
```bash
sudo systemctl status php8.3-fpm
sudo php-fpm8.3 -t                 # test config
```

### Restart / Reload
```bash
sudo systemctl reload php8.3-fpm   # graceful — finishes active requests
sudo systemctl restart php8.3-fpm  # full restart
```

### Tune Pool Workers
```bash
sudo nano /etc/php/8.3/fpm/pool.d/www.conf
```
```ini
; Dynamic process management (recommended)
pm = dynamic
pm.max_children = 20        ; max PHP workers (depends on RAM)
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 8
pm.max_requests = 500       ; recycle workers after N requests (prevents memory leaks)
```

Rule of thumb: `pm.max_children = (available_RAM_MB - 256) / avg_PHP_process_MB`
Typical PHP process: 30-80MB depending on app.

```bash
sudo systemctl reload php8.3-fpm
```

### View PHP Error Log
```bash
sudo tail -f /var/log/php8.3-fpm.log
# Also check per-app error logs if configured
```

---

## Node.js API Services

### Manage Any Registered Node.js Service
```bash
sudo systemctl status <service-name>
sudo systemctl restart <service-name>
sudo journalctl -u <service-name> -f
sudo journalctl -u <service-name> --since "1 hour ago" --no-pager
```

### Create New Node.js Service (Systemd Unit)
```bash
sudo nano /etc/systemd/system/<service-name>.service
```
```ini
[Unit]
Description=<App> API Service
After=network.target

[Service]
Type=simple
User=administrator
WorkingDirectory=/var/www/html/<app-folder>
ExecStart=/usr/bin/node <entry-point>.js
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=<port>

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl daemon-reload
sudo systemctl enable <service-name>
sudo systemctl start <service-name>
```

### Nginx Upstream Block For Node.js
```nginx
upstream <app>_backend {
    server 127.0.0.1:<port>;
}

server {
    ...
    location /api/ {
        proxy_pass http://<app>_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```
```

- [ ] **Step 2: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-webstack/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-webstack/SKILL.md
git commit -m "feat: add linux-webstack skill (Nginx, Apache, PHP-FPM, Node.js)"
```

---

## Task 11: linux-access-control

**Files:**
- Create: `/c/Users/Peter/.claude/skills/linux-access-control/SKILL.md`

- [ ] **Step 1: Create + write**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-access-control"
```

Write `/c/Users/Peter/.claude/skills/linux-access-control/SKILL.md`:

```markdown
---
name: linux-access-control
description: Manage users, groups, SSH keys, sudo access, and file permissions on Ubuntu/Debian servers. Create/delete users, manage sudo group, add/revoke SSH authorized_keys, audit who has access, fix file permission issues in web roots and system files.
---
# Access Control

## User Management

### Create A User
```bash
sudo adduser <username>                 # interactive (sets password, creates home)
sudo usermod -aG sudo <username>        # add to sudo group
```

### Delete A User
```bash
sudo deluser <username>                 # removes user, keeps home dir
sudo deluser --remove-home <username>   # removes user and home dir
```

### Lock / Unlock An Account
```bash
sudo passwd -l <username>              # lock (disables password login)
sudo passwd -u <username>              # unlock
```

### List All Users With Login Shell
```bash
grep -v "nologin\|false" /etc/passwd | cut -d: -f1,3,6,7
```

### Check sudo Group Members
```bash
grep ^sudo /etc/group
getent group sudo
```

---

## SSH Key Management

### Add A Key For A User
```bash
# As that user (or with their home dir):
mkdir -p /home/<username>/.ssh
chmod 700 /home/<username>/.ssh
echo "<public-key-content>" >> /home/<username>/.ssh/authorized_keys
chmod 600 /home/<username>/.ssh/authorized_keys
chown -R <username>:<username> /home/<username>/.ssh
```

### Audit All Authorized Keys On The Server
```bash
find /home /root -name authorized_keys 2>/dev/null | while read f; do
    echo "=== $f ==="
    cat "$f"
done
```

### Revoke A Key
```bash
# Edit the file and remove the line containing the key:
sudo nano /home/<username>/.ssh/authorized_keys
# Delete the line for the key being revoked
```

### Test SSH Config Before Restarting
```bash
sudo sshd -t && sudo systemctl restart sshd
# ALWAYS keep an existing session open while testing SSH changes
```

---

## File Permissions

### Web Root — Standard Permissions
```bash
# Directories: 755 | Files: 644 | Owner: www-data
sudo find /var/www -type d -exec chmod 755 {} \;
sudo find /var/www -type f -exec chmod 644 {} \;
sudo chown -R www-data:www-data /var/www/html/

# Remove world-writable files
sudo find /var/www -type f -perm -0002 -exec chmod o-w {} \;
```

### Critical System File Permissions
```bash
sudo chmod 640 /etc/shadow /etc/gshadow
sudo chmod 644 /etc/passwd /etc/group
sudo chmod 644 /etc/ssh/sshd_config
```

### Backup Credential Files (Must Be 600)
```bash
chmod 600 ~/.mysql-backup.cnf
chmod 600 ~/.backup-encryption-key
chmod 600 ~/.config/rclone/rclone.conf
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

### Find Permission Problems
```bash
# World-writable files in web root:
find /var/www -type f -perm -0002 2>/dev/null

# SUID/SGID files (unexpected ones are suspicious):
find / -perm /6000 -type f 2>/dev/null

# Unowned files:
find /var/www /home -nouser -nogroup 2>/dev/null
```

---

## Service Account Isolation

Web processes must run as `www-data`, not `root`:

```bash
ps aux | grep nginx | grep -v grep     # worker processes should show www-data
ps aux | grep php-fpm | grep -v grep   # pool workers should show www-data
```

Check Nginx worker user in `/etc/nginx/nginx.conf`:
```nginx
user www-data;
```

Check PHP-FPM pool user in `/etc/php/8.3/fpm/pool.d/www.conf`:
```ini
user = www-data
group = www-data
```
```

- [ ] **Step 2: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-access-control/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-access-control/SKILL.md
git commit -m "feat: add linux-access-control skill"
```

---

## Task 12: linux-system-monitoring

**Files:**
- Create: `/c/Users/Peter/.claude/skills/linux-system-monitoring/SKILL.md`

- [ ] **Step 1: Create + write**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-system-monitoring"
```

Write `/c/Users/Peter/.claude/skills/linux-system-monitoring/SKILL.md`:

```markdown
---
name: linux-system-monitoring
description: Monitor system health on Ubuntu/Debian servers. CPU load, memory usage, disk I/O, network connections, process inspection. Covers htop, iostat, vmstat, ss/netstat, and a quick one-liner health check. Includes what to look for and when to be concerned. Reference-style — outputs commands and how to read them.
---
# System Monitoring

## Quick Health Check (One Liner)
```bash
echo "=== LOAD ===" && uptime && \
echo "=== MEMORY ===" && free -h && \
echo "=== DISK ===" && df -h && \
echo "=== SERVICES ===" && \
systemctl is-active nginx mysql php8.3-fpm apache2 fail2ban | \
    paste - - - - - | column -t && \
echo "=== BACKUPS ===" && ls -lt ~/backups/ 2>/dev/null | head -3
```

---

## CPU & Load

```bash
uptime
# Output: load average: 1.23, 0.95, 0.88 (1m, 5m, 15m)
# Concern: load > number of CPU cores sustained for >5 min

nproc                          # how many CPU cores

htop                           # interactive: press P (CPU sort), M (memory sort), q (quit)

top -bn1 | head -20            # non-interactive snapshot
```

Reading load averages:
- `< nproc`: healthy
- `= nproc`: running at capacity
- `> nproc`: overloaded (investigate immediately)

---

## Memory

```bash
free -h
# Used + buff/cache = total used; available = actually free for new processes
# No swap on this server — when available memory → 0, OOM killer fires

# Processes using most RAM:
ps aux --sort=-%mem | head -15
ps aux --sort=-%mem | awk '{print $11, $6/1024 " MB"}' | head -10
```

Warning signs:
- `available` < 500MB → investigate and free memory
- `used` approaching total → OOM risk

---

## Disk I/O

```bash
iostat -x 1 5
# Key columns: %util (disk busy %), await (avg wait ms), r/s, w/s

# Which process is doing the I/O?
iotop -o                        # requires: sudo apt install iotop
sudo iotop -bod 5               # batch mode, 5 iterations
```

Warning signs:
- `%util` > 80% consistently = I/O bottleneck
- `await` > 50ms = slow disk response

---

## Network Connections

```bash
ss -tunapl                     # all TCP/UDP sockets with process info

# Count connections by state:
ss -tan | awk '{print $1}' | sort | uniq -c | sort -rn

# Connections to Nginx:
ss -tan | grep ':443\|:80' | grep ESTABLISHED | wc -l

# All listening services:
ss -tlnp

# Check specific port:
ss -tlnp | grep :3306           # MySQL
ss -tlnp | grep :6379           # Redis
```

---

## Process Inspection

```bash
# All processes:
ps aux

# Find a specific process:
ps aux | grep nginx

# Processes sorted by CPU:
ps aux --sort=-%cpu | head -10

# Processes sorted by memory:
ps aux --sort=-%mem | head -10

# Process tree:
pstree -p

# Kill a runaway process:
kill -15 <pid>                  # graceful SIGTERM
kill -9 <pid>                   # force SIGKILL (last resort)
```

---

## System Activity (vmstat)

```bash
vmstat 1 10
# Columns to watch:
# r = processes waiting for CPU (> nproc = bottleneck)
# b = processes in uninterruptible sleep (I/O wait)
# si/so = swap in/out (should be 0 — no swap on this server)
# wa = % CPU waiting for I/O (> 20% = disk bottleneck)
```

---

## Backup Health Check

```bash
# Is the backup cron running?
crontab -l | grep -i backup

# When was the last backup?
ls -lt ~/backups/mysql/*.gpg 2>/dev/null | head -3
# Last modified should be within last 3 hours

# rclone remote accessible?
rclone about gdrive: 2>/dev/null | head -2
```

---

## Per-Service Resource Usage

```bash
# Memory and CPU per service (requires systemd):
systemctl status nginx --no-pager | grep -E "Memory:|CPU:"
systemctl status mysql --no-pager | grep -E "Memory:|CPU:"
systemctl status php8.3-fpm --no-pager | grep -E "Memory:|CPU:"

# Or use:
ps aux | grep -E "nginx|mysql|php-fpm|apache" | awk '{sum[$11]+=$6} END {for(p in sum) print sum[p]/1024" MB", p}' | sort -rn
```
```

- [ ] **Step 2: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-system-monitoring/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-system-monitoring/SKILL.md
git commit -m "feat: add linux-system-monitoring skill"
```

---

## Task 13: linux-disk-storage

**Files:**
- Create: `/c/Users/Peter/.claude/skills/linux-disk-storage/SKILL.md`

- [ ] **Step 1: Create + write**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-disk-storage"
```

Write `/c/Users/Peter/.claude/skills/linux-disk-storage/SKILL.md`:

```markdown
---
name: linux-disk-storage
description: Manage disk space on Ubuntu/Debian servers. Analyse usage, find what's consuming space, safe cleanup targets (apt cache, old logs, journal, old backups, node_modules), inode usage, and emergency disk-full recovery. Includes swapfile creation for servers without swap.
---
# Disk & Storage Management

## Check Disk Usage

```bash
df -h                           # filesystem usage overview
df -h /                         # root partition specifically
df -i                           # inode usage (sometimes inodes full, not space)

# What's using the most space?
du -sh /var/www/* | sort -rh | head -10
du -sh /var/log/* 2>/dev/null | sort -rh | head -10
du -sh /home/* 2>/dev/null | sort -rh | head -10
du -sh ~/backups/* 2>/dev/null | sort -rh | head -5

# Find large files anywhere on the system:
sudo find / -type f -size +100M 2>/dev/null | sort -k5 -rn | head -20
sudo find / -type f -size +500M 2>/dev/null
```

---

## Safe Cleanup Targets

### APT Cache
```bash
sudo apt clean                   # removes all cached .deb files
sudo apt autoremove              # removes unused packages
du -sh /var/cache/apt/           # check savings
```

### System Journal Logs
```bash
sudo journalctl --disk-usage
sudo journalctl --vacuum-time=14d        # delete logs older than 14 days
sudo journalctl --vacuum-size=500M       # cap journal at 500MB
```

### Old Nginx/Apache Logs
```bash
ls -lh /var/log/nginx/
ls -lh /var/log/apache2/
# logrotate handles these — check config:
cat /etc/logrotate.d/nginx
# Force rotate if needed:
sudo logrotate -f /etc/logrotate.d/nginx
```

### Old Backup Files
```bash
# Local backups (retention script should handle this automatically)
ls -lth ~/backups/mysql/ | tail -20     # check oldest files
# Manual cleanup if needed:
find ~/backups/mysql/ -name "*.gpg" -mtime +7 -delete
```

### node_modules (After Build)
```bash
# After Astro build, node_modules can be cleaned (site runs from /dist/):
du -sh /var/www/html/*/node_modules 2>/dev/null | sort -rh | head -10

# Remove node_modules for built static sites (safe if build succeeded):
# cd /var/www[/html]/<folder>
# rm -rf node_modules
# (update-all-repos will reinstall on next update)
```

---

## Emergency Disk Full Recovery

When `df -h` shows 100% used:

```bash
# Step 1: Identify the culprit fast
du -sh /* 2>/dev/null | sort -rh | head -10
du -sh /var/* 2>/dev/null | sort -rh | head -10

# Step 2: Quick wins (safe, immediate):
sudo apt clean
sudo journalctl --vacuum-size=200M

# Step 3: Find and remove orphaned large files
sudo find /tmp /var/tmp -type f -mtime +7 -delete

# Step 4: Check for large log files that weren't rotated
sudo find /var/log -type f -size +100M -exec ls -lh {} \;
# Truncate (not delete) a log file:
sudo truncate -s 0 /var/log/<large-log-file>

# Step 5: Verify space recovered
df -h
```

---

## Inode Exhaustion

If `df -i` shows 100% inode usage (but disk space is available):

```bash
# Find directory with most files:
sudo find / -xdev -type f 2>/dev/null | cut -d/ -f2 | sort | uniq -c | sort -rn | head

# Common causes: many small session/cache files, mail spool
sudo find /var/lib/php/sessions/ -type f | wc -l   # PHP sessions
sudo find /tmp -type f | wc -l
```

---

## Swapfile (For Servers Without Swap)

Servers without swap risk OOM kills. Add a swapfile as safety net:

```bash
# Create 2GB swapfile:
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent:
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Set swappiness (low = only use swap in emergencies):
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.d/99-swappiness.conf
sudo sysctl vm.swappiness=10

# Verify:
free -h                         # Swap line should show 2G
swapon --show
```
```

- [ ] **Step 2: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-disk-storage/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-disk-storage/SKILL.md
git commit -m "feat: add linux-disk-storage skill"
```

---

## Task 14: linux-log-management

**Files:**
- Create: `/c/Users/Peter/.claude/skills/linux-log-management/SKILL.md`

- [ ] **Step 1: Create + write**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-log-management"
```

Write `/c/Users/Peter/.claude/skills/linux-log-management/SKILL.md`:

```markdown
---
name: linux-log-management
description: Read and manage logs on Ubuntu/Debian servers. journalctl filtering by service/time/priority. Nginx and Apache access and error log analysis. fail2ban ban log. MySQL slow query log. PHP error log. Backup cron log. logrotate configuration and forcing rotation. Finding attack patterns, 4xx/5xx spikes, and error bursts.
---
# Log Management

## journalctl — Systemd Logs

```bash
# All logs, last 100 lines:
sudo journalctl -n 100 --no-pager

# Specific service:
sudo journalctl -u nginx -n 50 --no-pager
sudo journalctl -u mysql -n 50 --no-pager
sudo journalctl -u php8.3-fpm -n 50 --no-pager
sudo journalctl -u fail2ban -n 50 --no-pager

# Follow live:
sudo journalctl -u nginx -f

# Time range:
sudo journalctl --since "2 hours ago"
sudo journalctl --since "2026-04-09 10:00" --until "2026-04-09 12:00"

# Priority (err, warning, info, debug):
sudo journalctl -p err --since "today" --no-pager

# Kernel messages (OOM kills, hardware errors):
sudo journalctl -k --since "today" | grep -iE "oom|error|fail"

# Disk usage:
sudo journalctl --disk-usage
```

---

## Nginx Logs

```bash
# Log locations:
# /var/log/nginx/access.log
# /var/log/nginx/error.log
# Per-domain logs if configured in vhost: /var/log/nginx/<domain>-*.log

# Live error monitoring:
sudo tail -f /var/log/nginx/error.log

# Find recent errors:
sudo grep -E "error|crit|alert|emerg" /var/log/nginx/error.log | tail -20

# Count requests by IP (find heavy hitters):
sudo awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -20

# Count HTTP status codes (find 4xx/5xx spikes):
sudo awk '{print $9}' /var/log/nginx/access.log | sort | uniq -c | sort -rn

# Find 5xx errors in access log:
sudo grep '" 5' /var/log/nginx/access.log | tail -20

# Most requested URLs:
sudo awk '{print $7}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -20
```

---

## Apache Logs (Port 8080 Backend)

```bash
sudo tail -f /var/log/apache2/error.log
sudo tail -f /var/log/apache2/access.log

# Find PHP errors:
sudo grep -i "php\|fatal\|error" /var/log/apache2/error.log | tail -20
```

---

## fail2ban Log

```bash
sudo tail -f /var/log/fail2ban.log

# Find recent bans:
sudo grep "Ban" /var/log/fail2ban.log | tail -20

# Bans by jail today:
sudo grep "$(date '+%Y-%m-%d')" /var/log/fail2ban.log | grep "Ban" | \
    awk '{print $6}' | sort | uniq -c | sort -rn

# Find which IP was banned the most:
sudo grep "Ban" /var/log/fail2ban.log | awk '{print $NF}' | sort | uniq -c | sort -rn | head
```

---

## MySQL Slow Query Log

```bash
# Enable slow query log (if not already on):
mysql -e "SET GLOBAL slow_query_log = 'ON';" 2>/dev/null
mysql -e "SET GLOBAL long_query_time = 2;" 2>/dev/null    # queries > 2 seconds

# Check if enabled:
mysql -e "SHOW VARIABLES LIKE 'slow_query_log%';" 2>/dev/null

# Read the log:
sudo tail -50 /var/log/mysql/mysql-slow.log 2>/dev/null

# Summarise slow queries:
sudo mysqldumpslow -s t -t 10 /var/log/mysql/mysql-slow.log 2>/dev/null
```

---

## PHP Error Log

```bash
# Find PHP error log location:
php -r "echo ini_get('error_log');" 2>/dev/null
# Typically: /var/log/php8.3-fpm.log or /var/log/php_errors.log

sudo tail -f /var/log/php8.3-fpm.log
sudo grep -i "fatal\|error" /var/log/php8.3-fpm.log | tail -20
```

---

## Backup Logs

```bash
# MySQL backup cron log:
tail -50 ~/backups/mysql/cron.log

# App backup cron log (root cron):
sudo tail -50 /backups/<app>/cron.log 2>/dev/null
```

---

## logrotate

```bash
# Check current rotation configs:
ls /etc/logrotate.d/
cat /etc/logrotate.d/nginx

# Force rotation now (useful after log grew too large):
sudo logrotate -f /etc/logrotate.d/nginx
sudo logrotate -f /etc/logrotate.d/apache2
sudo logrotate -f /etc/logrotate.d/mysql

# Add a new log to rotation:
sudo nano /etc/logrotate.d/<service>
```

Standard logrotate config template:
```
/var/log/<service>/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        systemctl reload <service> > /dev/null 2>&1 || true
    endscript
}
```

---

## Finding Attack Patterns

```bash
# Brute-force attempts on any URL:
sudo grep -E "POST.*(login|admin|wp-login|xmlrpc)" /var/log/nginx/access.log | \
    awk '{print $1}' | sort | uniq -c | sort -rn | head -10

# Scanner/bot activity (high 404 rate from one IP):
sudo awk '$9 == 404 {print $1}' /var/log/nginx/access.log | \
    sort | uniq -c | sort -rn | head -10

# Attempts to access .env, .git, config files:
sudo grep -E "\.(env|git|htaccess|sql|bak|config)" /var/log/nginx/access.log | tail -20
```
```

- [ ] **Step 2: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-log-management/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-log-management/SKILL.md
git commit -m "feat: add linux-log-management skill"
```

---

## Task 15: linux-server-provisioning

**Files:**
- Create: `/c/Users/Peter/.claude/skills/linux-server-provisioning/SKILL.md`

- [ ] **Step 1: Create + write**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-server-provisioning"
```

Write `/c/Users/Peter/.claude/skills/linux-server-provisioning/SKILL.md`:

```markdown
---
name: linux-server-provisioning
description: Set up a fresh Ubuntu/Debian server from scratch for production web hosting. Interactive step-by-step — covers hostname, timezone, admin user, SSH hardening, UFW baseline, full stack installation (Nginx, Apache, PHP-FPM, MySQL, PostgreSQL, Redis, Node.js, fail2ban, certbot, rclone, msmtp), and post-install security verification.
---
# Server Provisioning

Fresh Ubuntu/Debian server setup. Work through each section in order.
Ask before starting: What is the server hostname? What timezone? (default: Africa/Nairobi)

---

## 1. Initial System Setup

```bash
# Update everything first
sudo apt update && sudo apt upgrade -y

# Set hostname
sudo hostnamectl set-hostname <server-name>
echo "127.0.1.1 <server-name>" | sudo tee -a /etc/hosts

# Set timezone
sudo timedatectl set-timezone Africa/Nairobi
timedatectl                             # verify

# Set locale
sudo locale-gen en_GB.UTF-8
sudo update-locale LANG=en_GB.UTF-8
```

---

## 2. Admin User

```bash
# Create admin user (if not already exists)
sudo adduser administrator
sudo usermod -aG sudo administrator

# Copy SSH key from root (if initial login was as root):
sudo mkdir -p /home/administrator/.ssh
sudo cp /root/.ssh/authorized_keys /home/administrator/.ssh/
sudo chown -R administrator:administrator /home/administrator/.ssh
sudo chmod 700 /home/administrator/.ssh
sudo chmod 600 /home/administrator/.ssh/authorized_keys

# Test SSH login as administrator in a NEW terminal before continuing
# ssh administrator@<server-ip>
```

---

## 3. SSH Hardening

```bash
sudo nano /etc/ssh/sshd_config.d/99-hardening.conf
```
```
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 3
```
```bash
sudo sshd -t && sudo systemctl restart sshd
# Verify login still works from second terminal before closing first
```

---

## 4. UFW Firewall

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status verbose
```

---

## 5. Automatic Security Updates

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure unattended-upgrades    # select Yes
```

---

## 6. Web Stack Installation

```bash
# Nginx
sudo apt install -y nginx
sudo systemctl enable nginx

# Apache (backend, port 8080)
sudo apt install -y apache2
# Change Apache to listen on port 8080:
sudo nano /etc/apache2/ports.conf
# Change: Listen 80 → Listen 8080
sudo nano /etc/apache2/sites-available/000-default.conf
# Change: <VirtualHost *:80> → <VirtualHost *:8080>
sudo systemctl enable apache2
sudo systemctl restart apache2

# PHP 8.3 + FPM + common extensions
sudo apt install -y php8.3-fpm php8.3-cli php8.3-mysql php8.3-pgsql \
    php8.3-curl php8.3-mbstring php8.3-xml php8.3-zip php8.3-gd \
    php8.3-redis php8.3-intl php8.3-bcmath
sudo systemctl enable php8.3-fpm
```

---

## 7. Database Installation

```bash
# MySQL 8
sudo apt install -y mysql-server
sudo systemctl enable mysql
sudo mysql_secure_installation

# Bind MySQL to localhost only:
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
# Set: bind-address = 127.0.0.1
sudo systemctl restart mysql
ss -tlnp | grep 3306   # verify: 127.0.0.1:3306 only

# PostgreSQL 15
sudo apt install -y postgresql postgresql-contrib
sudo systemctl enable postgresql

# Redis
sudo apt install -y redis-server
sudo systemctl enable redis
# Set password and bind in /etc/redis/redis.conf
```

---

## 8. Supporting Tools

```bash
# Node.js (via NodeSource for latest LTS)
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs

# fail2ban
sudo apt install -y fail2ban
sudo systemctl enable fail2ban

# Certbot (nginx + apache plugins)
sudo apt install -y certbot python3-certbot-nginx python3-certbot-apache

# rclone
curl https://rclone.org/install.sh | sudo bash

# msmtp (for backup alert emails)
sudo apt install -y msmtp msmtp-mta
```

---

## 9. Nginx Configuration

```bash
# Set up shared snippets directory
sudo mkdir -p /etc/nginx/snippets

# security-dotfiles.conf — block .env, .git, .htaccess
sudo nano /etc/nginx/snippets/security-dotfiles.conf
```
```nginx
location ~ /\. { deny all; return 404; }
location ~ \.(env|git|sql|bak|config|htpasswd)$ { deny all; return 404; }
```
```bash
# ssl-params.conf
sudo nano /etc/nginx/snippets/ssl-params.conf
```
```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_stapling on;
ssl_stapling_verify on;
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
```
```bash
# proxy-to-apache.conf
sudo nano /etc/nginx/snippets/proxy-to-apache.conf
```
```nginx
proxy_pass http://127.0.0.1:8080;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
```
```bash
# nginx.conf — add server_tokens off and gzip
sudo nano /etc/nginx/nginx.conf
# Add inside http { }: server_tokens off;

# Default catch-all (rejects unknown hostnames):
sudo nano /etc/nginx/sites-available/00-default.conf
```
```nginx
server {
    listen 80 default_server;
    listen 443 ssl default_server;
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    return 444;
}
```
```bash
sudo ln -s /etc/nginx/sites-available/00-default.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

---

## 10. Clone Linux Skills Repo & Setup Scripts

```bash
cd /home/administrator
git clone <linux-skills-repo-url> linux-skills

# Symlink audit script
sudo ln -s /home/administrator/linux-skills/scripts/server-audit.sh \
    /usr/local/bin/check-server-security

# Install update-all-repos
sudo cp /home/administrator/linux-skills/scripts/update-all-repos \
    /usr/local/bin/update-all-repos
sudo chmod +x /usr/local/bin/update-all-repos
# Create wrapper:
echo -e '#!/bin/bash\n/usr/local/bin/update-all-repos "$@"' | \
    sudo tee /usr/local/bin/update-repos
sudo chmod +x /usr/local/bin/update-repos
```

---

## 11. Post-Install Security Check

```bash
sudo check-server-security
# Fix any FAIL items before putting the server into production
```

Reference: `~/linux-skills/notes/server-security.md` for hardening guide.
Next step: Run `linux-server-hardening` to apply full security hardening.
```

- [ ] **Step 2: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-server-provisioning/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-server-provisioning/SKILL.md
git commit -m "feat: add linux-server-provisioning skill (full Ubuntu/Debian setup)"
```

---

## Self-Review

### Spec Coverage Check

| Spec requirement | Task covering it |
|---|---|
| Hub with numbered menu + routing | Task 1 |
| Deep 10-layer security analysis | Task 2 |
| Interactive hardening walkthrough | Task 3 |
| Site deployment (3 patterns, 8 steps) | Task 4 |
| Service management (all 10 services) | Task 5 |
| Troubleshooting (8 symptom branches) | Task 6 |
| Disaster recovery (GPG decrypt + restore) | Task 7 |
| UFW + certbot SSL management | Task 8 |
| fail2ban + AIDE + auditd | Task 9 |
| Nginx + Apache + PHP-FPM + Node.js | Task 10 |
| Users, SSH keys, file permissions | Task 11 |
| CPU, memory, disk, network monitoring | Task 12 |
| Disk cleanup, swapfile | Task 13 |
| journalctl, web logs, logrotate | Task 14 |
| Fresh server from scratch | Task 15 |

All spec requirements covered. No gaps.

### Placeholder Scan

No TBD, TODO, "similar to above", or vague instructions found.
All tasks contain actual commands, exact file paths, and real content.

### Type Consistency

No shared types or function signatures across tasks — each skill is independent markdown.

---

*Plan written: 2026-04-09*
*Spec: docs/superpowers/specs/2026-04-09-linux-server-skills-design.md*
*Skills destination: C:\Users\Peter\.claude\skills\*
