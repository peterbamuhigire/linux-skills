# Linux Server Skills — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create 15 Claude Code skills (1 hub + 14 spokes) for managing production Ubuntu/Debian servers.

**Architecture:** Hub skill presents a numbered menu and routes to 14 focused spoke skills. Each skill is a directory with a `SKILL.md` (≤500 lines, orchestration + key commands) and a `references/` folder for deep-dive content. Reference files are created now as basics — expanded later with book content.

**Tech Stack:** Markdown, YAML frontmatter, bash/systemd/nginx/mysql/ufw commands

**Spec:** `docs/superpowers/specs/2026-04-09-linux-server-skills-design.md`

---

## Two-Tier Structure

Every skill follows this layout:

```
linux-<name>/
├── SKILL.md              ≤500 lines — workflow, key commands, links to references
└── references/
    └── *.md              Deep-dive content — expanded over time with book knowledge
```

**SKILL.md** = the interactive layer. Contains: frontmatter, workflow, the most-used commands, and `See references/<file>.md for more detail` pointers.

**references/** = the knowledge layer. Starts as basics. Gets richer as you add content from books and experience.

---

## Full File Structure

All files in `C:\Users\Peter\.claude\skills\`:

```
linux-sysadmin/
└── SKILL.md

linux-security-analysis/
├── SKILL.md
└── references/
    └── audit-layers.md         (10-layer command reference)

linux-server-hardening/
├── SKILL.md
└── references/
    └── hardening-checklist.md  (full configs and commands per item)

linux-site-deployment/
├── SKILL.md
└── references/
    └── nginx-templates.md      (Pattern A/B/C Nginx config templates)

linux-service-management/
├── SKILL.md
└── references/
    └── service-reference.md    (per-service operations and quirks)

linux-troubleshooting/
├── SKILL.md
└── references/
    └── diagnosis-tree.md       (full symptom → diagnosis → fix branches)

linux-disaster-recovery/
├── SKILL.md
└── references/
    └── restore-procedures.md   (full GPG decrypt + restore steps)

linux-firewall-ssl/
├── SKILL.md
└── references/
    └── ssl-config.md           (ssl-params.conf, certbot patterns)

linux-intrusion-detection/
├── SKILL.md
└── references/
    └── fail2ban-jails.md       (jail configs and filter templates)

linux-webstack/
├── SKILL.md
└── references/
    └── config-patterns.md      (Nginx, Apache, PHP-FPM config patterns)

linux-access-control/
├── SKILL.md
└── references/
    └── permissions-reference.md (permission patterns, SSH key management)

linux-system-monitoring/
├── SKILL.md
└── references/
    └── monitoring-commands.md  (full command reference with output interpretation)

linux-disk-storage/
├── SKILL.md
└── references/
    └── storage-reference.md    (cleanup targets, swapfile, LVM basics)

linux-log-management/
├── SKILL.md
└── references/
    └── log-locations.md        (all log paths, logrotate templates)

linux-server-provisioning/
├── SKILL.md
└── references/
    └── provisioning-steps.md   (full step-by-step installation guide)
```

---

## Task 1: linux-sysadmin (Hub)

**Files:**
- Create: `linux-sysadmin/SKILL.md`

- [ ] **Step 1: Create directory**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-sysadmin"
```

- [ ] **Step 2: Write SKILL.md**

Write `/c/Users/Peter/.claude/skills/linux-sysadmin/SKILL.md`:

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
Nginx cfg: /etc/nginx/sites-available/*.conf | snippets: /etc/nginx/snippets/
```

## What Do You Need To Do?

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

| Choice | Skill |
|--------|-------|
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

## Standing Rules

- All skills work on any Ubuntu/Debian server — no product names in guidance
- Confirm before every destructive operation (restore, drop, reset, delete)
- Run `sudo nginx -t` before every Nginx reload — never skip
- Every new repo on the server MUST be registered in `/usr/local/bin/update-all-repos`
- `update-all-repos` runs `git reset --hard` — local changes are destroyed on pull
- Backup credential files must always be mode 600
```

- [ ] **Step 3: Verify**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-sysadmin/SKILL.md"
# Must be ≤ 500 lines
```

- [ ] **Step 4: Commit**

```bash
cd "/c/Users/Peter/.claude/skills"
git add linux-sysadmin/
git commit -m "feat: add linux-sysadmin hub skill"
```

---

## Task 2: linux-security-analysis

**Files:**
- Create: `linux-security-analysis/SKILL.md`
- Create: `linux-security-analysis/references/audit-layers.md`

- [ ] **Step 1: Create directories**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-security-analysis/references"
```

- [ ] **Step 2: Write SKILL.md**

Write `/c/Users/Peter/.claude/skills/linux-security-analysis/SKILL.md`:

```markdown
---
name: linux-security-analysis
description: Deep read-only security audit for Ubuntu/Debian servers. Runs 10-layer analysis (kernel, users, network, firewall, web server, databases, filesystem, IDS, backups, packages) and produces a CRITICAL/HIGH/MEDIUM/LOW severity report. Never modifies the system — use linux-server-hardening to fix findings.
---
# Linux Security Analysis

**Read-only.** This skill observes and reports. It never modifies anything.
Use `linux-server-hardening` to fix what this skill finds.

Work through all 10 layers in `references/audit-layers.md`.
For each finding output: `[SEVERITY] Description`
Levels: **CRITICAL** | **HIGH** | **MEDIUM** | **LOW** | **INFO** | **PASS**

---

## Quick Start

```bash
# Optional: run the lightweight audit script first for a quick overview
sudo check-server-security
# Or: sudo bash ~/linux-skills/scripts/server-audit.sh

# Then work through the 10 layers for the full deep analysis
```

## The 10 Layers

See `references/audit-layers.md` for the complete commands for each layer.

| Layer | Focus | Critical findings |
|-------|-------|-------------------|
| 1 | System & kernel | ASLR off, pending CVEs |
| 2 | Users & auth | Extra UID-0, empty passwords, SSH config |
| 3 | Network exposure | Databases on 0.0.0.0 |
| 4 | Firewall | UFW inactive, unexpected open ports |
| 5 | Web server | TLS 1.0/1.1, PHP exposes version, expired certs |
| 6 | Databases | MySQL/Redis/PG on 0.0.0.0, anon users |
| 7 | File system | World-writable web files, cred files not 600 |
| 8 | IDS & monitoring | fail2ban down, AIDE missing |
| 9 | Backup integrity | No recent backup, rclone unreachable |
| 10 | Packages | Security updates pending, unexpected services |

## Severity Guidelines

| Rating | Meaning | Example |
|--------|---------|---------|
| CRITICAL | Exploitable right now | Database on 0.0.0.0, SSH with password auth |
| HIGH | Serious risk | No firewall, expired SSL cert |
| MEDIUM | Should fix soon | AIDE not installed, 20+ pending updates |
| LOW | Best practice gap | X11 forwarding enabled |
| INFO | Informational | Optional tools not installed |
| PASS | Correctly configured | — |

## Report Format

After all 10 layers, output:

```
╔══════════════════════════════════════════════════════╗
║           SECURITY ANALYSIS REPORT                  ║
╠══════════════════════════════════════════════════════╣
║ Host: <hostname>  OS: <distro>  Date: <YYYY-MM-DD>  ║
╚══════════════════════════════════════════════════════╝

[CRITICAL] ...
[HIGH]     ...
[MEDIUM]   ...
[PASS]     ...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 CRITICAL: X  HIGH: X  MEDIUM: X  LOW: X  PASS: X
 Security score: X%
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Recommended: Run linux-server-hardening to fix CRITICAL and HIGH items first.
```
```

- [ ] **Step 3: Write references/audit-layers.md**

Write `/c/Users/Peter/.claude/skills/linux-security-analysis/references/audit-layers.md`:

```markdown
# Security Audit — Layer Command Reference

Complete commands for each of the 10 security analysis layers.

## Layer 1: System & Kernel

```bash
uname -r
sysctl kernel.randomize_va_space        # expect 2
sysctl kernel.dmesg_restrict            # expect 1
sysctl kernel.kptr_restrict             # expect 2
sysctl net.ipv4.tcp_syncookies          # expect 1
sysctl net.ipv4.conf.all.accept_redirects  # expect 0
sysctl net.ipv4.conf.all.send_redirects    # expect 0
sysctl net.ipv4.conf.all.rp_filter         # expect 1
apt list --upgradable 2>/dev/null | grep -i security | wc -l
systemctl is-enabled unattended-upgrades 2>/dev/null
```

CRITICAL: ASLR=0 | HIGH: >20 security updates | MEDIUM: unattended-upgrades off

## Layer 2: Users & Authentication

```bash
awk -F: '$3 == 0 {print $1}' /etc/passwd        # UID-0 (only root expected)
sudo awk -F: '$2 == "" {print $1}' /etc/shadow  # empty passwords
grep ^sudo /etc/group                            # sudo members
grep -rh "^PermitRootLogin\|^PasswordAuthentication\|^MaxAuthTries\|^X11Forwarding" \
    /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null
find /home /root -name authorized_keys 2>/dev/null -exec echo "=== {} ===" \; -exec cat {} \;
```

CRITICAL: extra UID-0 or empty passwords |
HIGH: PasswordAuthentication yes | HIGH: PermitRootLogin not 'no'

## Layer 3: Network Exposure

```bash
ss -tulnp
ss -tlnp | grep -E ':3306|:5432|:6379|:27017'  # must all be 127.0.0.1
ss -tlnp | grep ":::"                           # IPv6 listeners
```

CRITICAL: MySQL/PostgreSQL/Redis on 0.0.0.0

## Layer 4: Firewall

```bash
sudo ufw status verbose
sudo ufw status verbose | grep "Default:"       # must be 'deny (incoming)'
```

CRITICAL: UFW inactive | HIGH: default not deny | MEDIUM: unexpected ALLOW rules

## Layer 5: Web Server Security

```bash
sudo nginx -T 2>/dev/null | grep -E "server_tokens|ssl_protocols"
sudo certbot certificates 2>/dev/null
openssl s_client -connect localhost:443 -tls1 2>&1 | grep -E "handshake|alert"
php -r "echo ini_get('expose_php');"           # must be empty
php -r "echo ini_get('display_errors');"       # must be 0/empty
php -r "echo ini_get('allow_url_include');"    # must be empty
php -r "echo ini_get('session.cookie_secure');" # must be 1
php -r "echo ini_get('disable_functions');"    # must have entries
```

CRITICAL: cert expires <7 days | HIGH: TLSv1.0/1.1 accepted | HIGH: PHP exposes version

## Layer 6: Database Security

```bash
grep -E "^bind-address" /etc/mysql/mysql.conf.d/mysqld.cnf \
    /etc/mysql/mariadb.conf.d/50-server.cnf 2>/dev/null
mysql -e "SELECT user,host FROM mysql.user WHERE user='';" 2>/dev/null
mysql -e "SHOW DATABASES;" 2>/dev/null | grep "^test$"
grep -E "^bind|^requirepass" /etc/redis/redis.conf 2>/dev/null
grep -v "^#\|^$" /etc/postgresql/*/main/pg_hba.conf 2>/dev/null | head -10
```

CRITICAL: databases on 0.0.0.0 | HIGH: anon MySQL users | HIGH: Redis no password

## Layer 7: File System

```bash
find /var/www -type f -perm -0002 2>/dev/null
find / -perm /6000 -type f 2>/dev/null | \
    grep -vE "(sudo|passwd|su|mount|umount|ping|crontab|at|newgrp|chsh|chfn|gpasswd)"
stat -c "%a %n" ~/.mysql-backup.cnf ~/.backup-encryption-key \
    ~/.config/rclone/rclone.conf 2>/dev/null
stat -c "%a %n" /etc/shadow /etc/gshadow /etc/passwd /etc/ssh/sshd_config
find /var/www /home /etc -nouser -nogroup 2>/dev/null | head -10
```

HIGH: world-writable /var/www files | HIGH: cred files not 600 | MEDIUM: unexpected SUID

## Layer 8: Intrusion Detection & Monitoring

```bash
systemctl is-active fail2ban
sudo fail2ban-client status 2>/dev/null | grep -E "Number of jail|Jail list"
command -v aide >/dev/null 2>&1 && echo "AIDE installed" || echo "AIDE missing"
ls /var/lib/aide/aide.db 2>/dev/null || echo "AIDE DB not initialised"
systemctl is-active auditd 2>/dev/null
dpkg -l 2>/dev/null | grep -E "logwatch|logcheck"
```

HIGH: fail2ban not running | MEDIUM: AIDE not installed | MEDIUM: <3 jails

## Layer 9: Backup Integrity

```bash
crontab -l 2>/dev/null | grep -iE "backup|rclone"
sudo crontab -l 2>/dev/null | grep -iE "backup|rclone"
find ~/backups -name "*.gpg" -mtime -1 2>/dev/null | wc -l
rclone about gdrive: 2>/dev/null | head -2 || echo "rclone: cannot connect"
for f in ~/.mysql-backup.cnf ~/.backup-encryption-key ~/.config/rclone/rclone.conf; do
    [ -f "$f" ] && echo "EXISTS $f" || echo "MISSING $f"
done
```

HIGH: no backup in 24h | HIGH: backup creds missing | MEDIUM: rclone unreachable

## Layer 10: Packages & Software

```bash
apt list --upgradable 2>/dev/null | tail -n +2 | wc -l
systemctl list-units --type=service --state=running | \
    grep -vE "nginx|apache|mysql|postgresql|php|redis|fail2ban|ssh|cron|ufw|certbot|systemd|dbus|network"
command -v lynis >/dev/null 2>&1 && \
    sudo lynis audit system --quick 2>/dev/null | grep -E "Hardening index|Warning" | head -10
```

MEDIUM: >10 upgradable packages | INFO: unexpected running services
```

- [ ] **Step 4: Verify**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-security-analysis/SKILL.md"
wc -l "/c/Users/Peter/.claude/skills/linux-security-analysis/references/audit-layers.md"
# Both must be ≤ 500 lines
```

- [ ] **Step 5: Commit**

```bash
cd "/c/Users/Peter/.claude/skills"
git add linux-security-analysis/
git commit -m "feat: add linux-security-analysis skill (10-layer audit)"
```

---

## Task 3: linux-server-hardening

**Files:**
- Create: `linux-server-hardening/SKILL.md`
- Create: `linux-server-hardening/references/hardening-checklist.md`

- [ ] **Step 1: Create directories**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-server-hardening/references"
```

- [ ] **Step 2: Write SKILL.md**

Write `/c/Users/Peter/.claude/skills/linux-server-hardening/SKILL.md`:

```markdown
---
name: linux-server-hardening
description: Interactive security hardening for Ubuntu/Debian servers. Runs the audit script first, then walks through each FAIL and WARN item — asks before applying any change. Covers SSH, UFW, fail2ban, sysctl, Nginx, PHP-FPM, MySQL, Redis, file permissions, backup credential security.
---
# Linux Server Hardening

Applies security fixes interactively. Runs the audit first — never applies
a change without your confirmation.

**For a full picture first:** run `linux-security-analysis` before hardening.

---

## Step 1: Run The Audit

```bash
sudo check-server-security
# If not symlinked: sudo bash ~/linux-skills/scripts/server-audit.sh
```

Fix FAIL items first, then WARN. Use `references/hardening-checklist.md`
for the complete commands for each area.

---

## Hardening Areas (In Priority Order)

### 1. SSH
- Disable password auth, disable root login, set MaxAuthTries 3
- **WARNING:** Keep existing SSH session open. Test login in a second terminal
  before closing the first session.
- Config: `/etc/ssh/sshd_config.d/99-hardening.conf`
- Test before restart: `sudo sshd -t && sudo systemctl restart sshd`

### 2. Firewall (UFW)
- Default deny incoming, allow 22/80/443 only
- `sudo ufw status verbose` to check current state

### 3. Kernel (sysctl)
- Network stack hardening + ASLR + kernel pointer restriction
- Config: `/etc/sysctl.d/99-security.conf`
- Apply: `sudo sysctl --system`

### 4. Nginx
- `server_tokens off` in nginx.conf
- Security headers on all vhosts (or global security.conf)
- Dotfile blocking snippet included in all vhosts

### 5. PHP-FPM
- `expose_php = Off`, `display_errors = Off`, `allow_url_include = Off`
- Session cookie security settings
- `disable_functions` for dangerous functions
- Config: `/etc/php/8.3/fpm/php.ini`

### 6. MySQL
- `bind-address = 127.0.0.1` (never expose to network)
- Run `mysql_secure_installation`
- Application users: least-privilege only

### 7. Redis
- Bound to 127.0.0.1, password set, dangerous commands renamed

### 8. File Permissions
- `/etc/shadow` → 640, credential files → 600
- No world-writable files in `/var/www`
- SSH keys → 600

### 9. Automatic Updates
- `unattended-upgrades` installed and enabled

---

## Verify After Hardening

```bash
sudo check-server-security
# All previous FAIL items should now be PASS
```

Full configs and commands for each area: `references/hardening-checklist.md`
Reference guide: `~/linux-skills/notes/server-security.md`
```

- [ ] **Step 3: Write references/hardening-checklist.md**

Write `/c/Users/Peter/.claude/skills/linux-server-hardening/references/hardening-checklist.md`:

```markdown
# Hardening Checklist — Full Commands

## SSH Hardening

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
```bash
sudo sshd -t && sudo systemctl restart sshd
```

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

## Kernel Hardening (sysctl)

```bash
sudo nano /etc/sysctl.d/99-security.conf
```
```ini
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
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

## Nginx Security

```nginx
# In /etc/nginx/nginx.conf http block:
server_tokens off;
```
```bash
# Verify dotfile blocking in all vhosts:
sudo grep -r "security-dotfiles" /etc/nginx/sites-enabled/
# Verify security headers:
sudo grep -r "X-Frame-Options\|X-Content-Type" /etc/nginx/sites-enabled/ \
    /etc/nginx/conf.d/ /etc/nginx/snippets/
```

## PHP-FPM Security

```bash
sudo nano /etc/php/8.3/fpm/php.ini
```
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

## MySQL Security

```bash
# Bind to localhost:
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
# Set: bind-address = 127.0.0.1
sudo systemctl restart mysql
ss -tlnp | grep 3306   # must show 127.0.0.1:3306

# Secure installation (removes anon users, test DB):
sudo mysql_secure_installation
```

## Redis Security

```bash
sudo nano /etc/redis/redis.conf
# Ensure: bind 127.0.0.1 -::1
# Ensure: requirepass <strong-password>
# Add:
# rename-command FLUSHDB ""
# rename-command FLUSHALL ""
# rename-command CONFIG ""
# rename-command DEBUG ""
sudo systemctl restart redis
ss -tlnp | grep 6379   # must show 127.0.0.1:6379
```

## File Permissions

```bash
sudo chmod 640 /etc/shadow /etc/gshadow
sudo chmod 644 /etc/passwd /etc/group
chmod 600 ~/.mysql-backup.cnf ~/.backup-encryption-key
chmod 600 ~/.config/rclone/rclone.conf
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
sudo find /var/www -type f -perm -0002 -exec chmod o-w {} \;
```

## Automatic Updates

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure unattended-upgrades   # select Yes
cat /etc/apt/apt.conf.d/20auto-upgrades     # verify
```
```

- [ ] **Step 4: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-server-hardening/SKILL.md"
wc -l "/c/Users/Peter/.claude/skills/linux-server-hardening/references/hardening-checklist.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-server-hardening/
git commit -m "feat: add linux-server-hardening skill"
```

---

## Task 4: linux-site-deployment

**Files:**
- Create: `linux-site-deployment/SKILL.md`
- Create: `linux-site-deployment/references/nginx-templates.md`

- [ ] **Step 1: Create directories**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-site-deployment/references"
```

- [ ] **Step 2: Write SKILL.md**

Write `/c/Users/Peter/.claude/skills/linux-site-deployment/SKILL.md`:

```markdown
---
name: linux-site-deployment
description: Deploy a new website to an Ubuntu/Debian server running Nginx + Apache dual-stack. Interactive — asks domain name and site type (Astro static / PHP app / Astro+PHP hybrid), generates the correct Nginx config, walks the full 8-step deployment, issues SSL, and registers the repo in update-all-repos.
---
# Site Deployment

Ask these questions first:

1. **Domain name?** (e.g. example.com)
2. **Site type?**
   - **A** — Astro/static (Nginx serves `/dist/` directly)
   - **B** — PHP app (Nginx → Apache port 8080)
   - **C** — Astro + PHP hybrid (static front + PHP backend)
3. **Repo URL?**
4. **Node.js API needed?** (separate systemd service)

---

## The 8 Steps

### 1. Clone
```bash
cd /var/www/html   # or /var/www for some Astro sites
sudo git clone <repo-url> <folder-name>
```

### 2. Build (A and C only)
```bash
cd /var/www[/html]/<folder>
# Pattern A:  sudo npm install --production && sudo npm run build
# Pattern C:  sudo composer install --no-dev && sudo npm install --production && sudo npm run build
```

### 3. Create Nginx Config
```bash
sudo nano /etc/nginx/sites-available/<domain>.conf
```
See `references/nginx-templates.md` for the correct template per pattern.

### 4. Enable Site
```bash
sudo ln -s /etc/nginx/sites-available/<domain>.conf /etc/nginx/sites-enabled/
```

### 5. Test & Reload (mandatory)
```bash
sudo nginx -t && sudo systemctl reload nginx
# Fix any errors before continuing — never skip nginx -t
```

### 6. Issue SSL
```bash
sudo certbot --nginx -d <domain>
```

### 7. Apache Vhost (B and C only)
```bash
sudo nano /etc/apache2/sites-available/<domain>.conf
sudo a2ensite <domain>.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
```
See `references/nginx-templates.md` for Apache vhost template.

### 8. Register in update-all-repos (mandatory)
```bash
sudo nano /usr/local/bin/update-all-repos
# Add entry: "Display Name|/path/to/repo|build command"
```

Per `~/linux-skills/notes/new-repo-checklist.md` — this step is never optional.

**Build command by pattern:**
- A (Astro): `npm install --production && npm run build`
- B (PHP): *(leave empty)*
- C (Astro+PHP): `composer install --no-dev && npm install --production && npm run build`

**WARNING:** `update-all-repos` runs `git reset --hard`. Commit any server-side
changes to git before running it — they will be destroyed otherwise.

---

## Verify

```bash
curl -sI https://<domain> | grep -E "HTTP/|Server:"
sudo certbot certificates | grep -A3 "<domain>"
```

For Node.js API service setup, see `linux-webstack`.
Full Nginx/Apache config templates: `references/nginx-templates.md`
```

- [ ] **Step 3: Write references/nginx-templates.md**

Write `/c/Users/Peter/.claude/skills/linux-site-deployment/references/nginx-templates.md`:

```markdown
# Nginx & Apache Config Templates

## Pattern A — Astro Static Site

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

## Pattern B — PHP App (Nginx → Apache Port 8080)

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

## Pattern C — Astro + PHP Hybrid

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

## Apache Vhost (Pattern B and C — Port 8080)

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

## After Certbot Runs (SSL Block Added Automatically)

Certbot adds SSL directives and HTTP→HTTPS redirect to the Nginx config.
Verify `ssl-params.conf` snippet is included in the SSL block:

```nginx
# Inside the <VirtualHost *:443> or ssl server block, add if missing:
include snippets/ssl-params.conf;
```

## Nginx Proxy Snippet (/etc/nginx/snippets/proxy-to-apache.conf)

```nginx
proxy_pass http://127.0.0.1:8080;
proxy_http_version 1.1;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_connect_timeout 60s;
proxy_send_timeout 60s;
proxy_read_timeout 60s;
```

## Security Dotfiles Snippet (/etc/nginx/snippets/security-dotfiles.conf)

```nginx
location ~ /\. { deny all; return 404; }
location ~* \.(env|git|sql|bak|htpasswd|config)$ { deny all; return 404; }
```
```

- [ ] **Step 4: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-site-deployment/SKILL.md"
wc -l "/c/Users/Peter/.claude/skills/linux-site-deployment/references/nginx-templates.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-site-deployment/
git commit -m "feat: add linux-site-deployment skill (3 patterns, 8-step workflow)"
```

---

## Task 5: linux-service-management

**Files:**
- Create: `linux-service-management/SKILL.md`
- Create: `linux-service-management/references/service-reference.md`

- [ ] **Step 1: Create directories**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-service-management/references"
```

- [ ] **Step 2: Write SKILL.md**

Write `/c/Users/Peter/.claude/skills/linux-service-management/SKILL.md`:

```markdown
---
name: linux-service-management
description: Manage systemd services on Ubuntu/Debian servers. Start, stop, restart, reload, enable/disable on boot, view status and logs via journalctl. Covers all web server services (nginx, apache2, mysql, postgresql, php-fpm, redis, fail2ban, certbot, cron, msmtp) and Node.js product services. Includes crashed-service diagnosis workflow.
---
# Service Management

## Core Commands

```bash
sudo systemctl status <service>           # check status + last log lines
sudo systemctl start|stop|restart <service>
sudo systemctl reload <service>           # graceful (not all services support)
sudo systemctl enable|disable <service>   # boot behaviour
sudo systemctl is-active <service>
sudo systemctl is-enabled <service>
```

## Services Quick Reference

| Service | Safe reload? | Notes |
|---------|-------------|-------|
| `nginx` | Yes | Always run `nginx -t` first |
| `apache2` | Yes | Run `apache2ctl configtest` first |
| `mysql` | No | Brief downtime on restart |
| `postgresql` | Yes | reload re-reads postgresql.conf |
| `php8.3-fpm` | Yes | reload finishes active requests |
| `redis` | No | |
| `fail2ban` | Yes | reload re-reads jail configs |
| `certbot.timer` | — | systemd timer, not a daemon |
| `cron` | No | |
| `msmtp` | — | not a daemon; test with command |

Full per-service operations: `references/service-reference.md`

## Viewing Logs (journalctl)

```bash
sudo journalctl -u <service> -n 50 --no-pager     # last 50 lines
sudo journalctl -u <service> -f                   # follow live
sudo journalctl -u <service> --since "1 hour ago"
sudo journalctl -u <service> -p err --no-pager    # errors only
```

## Diagnosing A Crashed Service

```bash
# Step 1: Read exit code and recent logs
sudo systemctl status <service> --no-pager

# Step 2: Get full error context
sudo journalctl -u <service> --since "5 min ago" --no-pager

# Step 3: Test config (web servers)
sudo nginx -t                    # nginx
sudo apache2ctl configtest       # apache2
sudo php-fpm8.3 -t              # php-fpm

# Step 4: Check for disk full or port conflicts
df -h
sudo ss -tlnp | grep <port>
```

## Check All Services At Once

```bash
sudo systemctl list-units --type=service --state=failed
sudo systemctl list-units --type=service --state=running | \
    grep -E "nginx|apache|mysql|postgresql|php|redis|fail2ban"
```

## Node.js Services (Product-Specific)

```bash
# Any Node.js service registered in systemd:
sudo systemctl status <service-name>
sudo journalctl -u <service-name> -n 50 --no-pager
sudo systemctl restart <service-name>    # after code update via update-all-repos
```

For creating a new Node.js systemd unit, see `linux-webstack`.
```

- [ ] **Step 3: Write references/service-reference.md**

Write `/c/Users/Peter/.claude/skills/linux-service-management/references/service-reference.md`:

```markdown
# Per-Service Operations Reference

## nginx

```bash
sudo nginx -t                              # test config (ALWAYS before reload)
sudo nginx -t && sudo systemctl reload nginx
sudo systemctl restart nginx               # full restart (brief downtime)
sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

## apache2

```bash
sudo apache2ctl configtest                 # test config
sudo apache2ctl configtest && sudo systemctl reload apache2
sudo tail -f /var/log/apache2/error.log
```

## mysql

```bash
sudo systemctl restart mysql
sudo journalctl -u mysql --since "5 min ago" --no-pager
mysql -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null
mysql -e "SHOW PROCESSLIST;" 2>/dev/null
```

## postgresql

```bash
sudo systemctl reload postgresql           # re-reads postgresql.conf
sudo journalctl -u postgresql --since "5 min ago" --no-pager
sudo -u postgres psql -c "\l"             # list databases
```

## php8.3-fpm

```bash
sudo php-fpm8.3 -t                        # test config
sudo systemctl reload php8.3-fpm
# Tune workers:
sudo nano /etc/php/8.3/fpm/pool.d/www.conf
# Key: pm.max_children, pm.start_servers
sudo tail -f /var/log/php8.3-fpm.log
```

## redis

```bash
sudo systemctl restart redis
redis-cli ping                             # should return PONG
redis-cli -a <password> info server
```

## fail2ban

```bash
sudo systemctl reload fail2ban
sudo fail2ban-client status
sudo tail -f /var/log/fail2ban.log
```

## certbot.timer

```bash
sudo systemctl status certbot.timer
sudo certbot renew --dry-run               # test renewal
sudo certbot certificates                  # check expiry
```

## msmtp (test alert email)

```bash
echo "Subject: Test\n\nTest from $(hostname)" | \
    msmtp --debug --account=default <your@email.com>
cat /etc/msmtprc 2>/dev/null || cat ~/.msmtprc 2>/dev/null
```

## cron

```bash
crontab -l                                 # current user cron jobs
sudo crontab -l                            # root cron jobs
sudo systemctl restart cron
sudo journalctl -u cron --since "1 hour ago" --no-pager
```
```

- [ ] **Step 4: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-service-management/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-service-management/
git commit -m "feat: add linux-service-management skill"
```

---

## Task 6: linux-troubleshooting

**Files:**
- Create: `linux-troubleshooting/SKILL.md`
- Create: `linux-troubleshooting/references/diagnosis-tree.md`

- [ ] **Step 1: Create directories**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-troubleshooting/references"
```

- [ ] **Step 2: Write SKILL.md**

Write `/c/Users/Peter/.claude/skills/linux-troubleshooting/SKILL.md`:

```markdown
---
name: linux-troubleshooting
description: Systematic incident diagnosis for Ubuntu/Debian production servers. Ask for the symptom then follow the matching diagnosis branch — high CPU/load, OOM kill, disk full, service crashed, 502/504 errors, slow site, MySQL issues, SSL expired, backup failed, site down after git update.
---
# Troubleshooting

Ask: "What's the symptom?" then follow the branch in `references/diagnosis-tree.md`.

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

# Disk full → clear apt cache
sudo apt clean && sudo journalctl --vacuum-size=500M

# 502 → restart the upstream
sudo systemctl restart php8.3-fpm
sudo systemctl restart apache2

# SSL expired → force renew
sudo certbot renew --force-renewal
```
```

- [ ] **Step 3: Write references/diagnosis-tree.md**

Write `/c/Users/Peter/.claude/skills/linux-troubleshooting/references/diagnosis-tree.md`:

```markdown
# Diagnosis Tree — Full Branches

## Branch 1: High CPU / Load Average

```bash
uptime                              # load: 1m 5m 15m — concern if > nproc
nproc                               # CPU core count
htop                                # P = sort by CPU; identify top process
ps aux --sort=-%cpu | head -10
```

Fix: `sudo systemctl restart <service>` | `kill -9 <pid>` (last resort)

## Branch 2: OOM Kill

```bash
free -h                             # check available memory
sudo dmesg | grep -i "oom\|killed process" | tail -10
sudo journalctl -k --since "1 hour ago" | grep -i oom
ps aux --sort=-%mem | head -10
```

Fix: restart the killed service | add swapfile (`linux-disk-storage`) |
reduce `innodb_buffer_pool_size` if MySQL is the culprit

## Branch 3: Disk Full

```bash
df -h
du -sh /var/www/* | sort -rh | head -10
du -sh /var/log/* 2>/dev/null | sort -rh | head -10
sudo find / -type f -size +100M 2>/dev/null | head -10
```

Quick wins:
```bash
sudo apt clean
sudo journalctl --vacuum-size=500M
sudo find /tmp /var/tmp -type f -mtime +7 -delete
```

## Branch 4: Service Crashed

```bash
sudo systemctl status <service> --no-pager
sudo journalctl -u <service> --since "10 min ago" --no-pager
sudo nginx -t                        # for nginx
sudo apache2ctl configtest           # for apache2
sudo ss -tlnp | grep <port>          # port conflict?
```

## Branch 5: 502 / 504 Bad Gateway

```bash
sudo tail -20 /var/log/nginx/error.log
sudo systemctl status php8.3-fpm     # PHP sites
sudo systemctl status apache2        # Apache-proxied sites
ls -la /run/php/php8.3-fpm.sock      # FPM socket exists?

# Fix:
sudo systemctl restart php8.3-fpm
sudo systemctl restart apache2
```

## Branch 6: Slow Site

```bash
curl -w "\nTime: %{time_total}s\n" -o /dev/null -s https://<domain>
uptime && free -h                    # server load OK?
mysql -e "SHOW PROCESSLIST;" 2>/dev/null   # slow queries?
ps aux | grep php-fpm | wc -l       # FPM workers maxed?
sudo awk '{print $1}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head
```

## Branch 7: MySQL Issues

```bash
sudo systemctl status mysql
sudo journalctl -u mysql --since "10 min ago" --no-pager
ss -tlnp | grep 3306                 # is it running?
mysql -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null
df -h /var/lib/mysql                 # disk space for MySQL?
```

## Branch 8: SSL Expired / Renewal Failed

```bash
sudo certbot certificates            # check all expiry dates
sudo certbot renew --dry-run         # test renewal
sudo certbot renew --force-renewal   # force if needed
sudo grep "acme-challenge" /etc/nginx/sites-enabled/*.conf  # challenge path present?
sudo journalctl -u certbot --no-pager | tail -20
```

## Branch 9: Backup Failed

```bash
tail -50 ~/backups/mysql/cron.log    # did script run?
rclone about gdrive: 2>/dev/null     # rclone token OK?
rclone config reconnect gdrive:      # if token expired
ls -la ~/.backup-encryption-key      # GPG key present and mode 600?
# Test backup manually:
~/mysql-backup.sh
```

## Branch 10: Site Down After update-all-repos

```bash
sudo systemctl status nginx
sudo nginx -t                        # config broken by update?
sudo tail -20 /var/log/nginx/error.log

# Roll back to previous commit:
cd /var/www[/html]/<folder>
sudo git log --oneline -5
sudo git reset --hard <good-commit-hash>
sudo npm run build                   # if Astro site
sudo nginx -t && sudo systemctl reload nginx
```
```

- [ ] **Step 4: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-troubleshooting/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-troubleshooting/
git commit -m "feat: add linux-troubleshooting skill (10 diagnosis branches)"
```

---

## Task 7: linux-disaster-recovery

**Files:**
- Create: `linux-disaster-recovery/SKILL.md`
- Create: `linux-disaster-recovery/references/restore-procedures.md`

- [ ] **Step 1: Create directories**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-disaster-recovery/references"
```

- [ ] **Step 2: Write SKILL.md**

Write `/c/Users/Peter/.claude/skills/linux-disaster-recovery/SKILL.md`:

```markdown
---
name: linux-disaster-recovery
description: Restore from GPG-encrypted backups on Ubuntu/Debian servers. Covers MySQL database restore (single DB or full), app file restore, and emergency recovery checklist. Backups are AES256 GPG encrypted, stored locally and on Google Drive via rclone. Always confirms before any destructive restore.
---
# Disaster Recovery

**Always confirm before restoring.** A restore overwrites existing data.

---

## Step 1: Assess First

```bash
# Is this a service crash (restart only) or actual data loss?
sudo systemctl status nginx mysql postgresql php8.3-fpm

# When did it happen?
sudo journalctl --since "2 hours ago" | grep -iE "error|fail|crash" | head -20
```

Service crash → restart it (`linux-service-management`), no restore needed.
Data loss/corruption → proceed below.

## Step 2: Find The Right Backup

```bash
# Local backups (7-day retention)
ls -lth ~/backups/mysql/*.gpg 2>/dev/null | head -10

# Google Drive (3-day retention for MySQL)
rclone ls gdrive:<backup-folder> 2>/dev/null | sort | tail -10

# If rclone token expired:
rclone config reconnect gdrive:
```

Choose the backup **closest to before the incident**.

## Step 3: Restore

Full restore procedure (decrypt → extract → import):
See `references/restore-procedures.md`

## Emergency Checklist

```bash
# 1. Stop affected service to prevent further damage
sudo systemctl stop <service>

# 2. Find best backup (Step 2 above)

# 3. Decrypt → restore → verify (references/restore-procedures.md)

# 4. Restart all services
sudo systemctl start nginx mysql php8.3-fpm apache2

# 5. Re-run security audit
sudo check-server-security

# 6. Clean up
rm -rf ~/restore/
```

## Demo/Dev Reset (Git-Tracked SQL Dump Pattern)

Some apps ship a git-tracked SQL dump as the demo DB source of truth.
A reset script drops and recreates from that dump:

```bash
ls /usr/local/bin/reset-*           # find available reset scripts
sudo reset-<app>-from-git           # requires typing YES
ls /var/backups/<app>/              # safety backup always created first
```
```

- [ ] **Step 3: Write references/restore-procedures.md**

Write `/c/Users/Peter/.claude/skills/linux-disaster-recovery/references/restore-procedures.md`:

```markdown
# Restore Procedures

## MySQL Restore (GPG-Encrypted Backup)

### Download From Google Drive

```bash
mkdir -p ~/restore
rclone ls gdrive:<backup-folder> | sort | tail -10    # find backup name
rclone copy gdrive:<backup-folder>/mysql-backup_TIMESTAMP.tar.gz.gpg ~/restore/
```

### Decrypt

```bash
gpg --batch \
    --passphrase-file ~/.backup-encryption-key \
    -d ~/restore/mysql-backup_TIMESTAMP.tar.gz.gpg \
    > ~/restore/mysql-backup_TIMESTAMP.tar.gz

ls -lh ~/restore/mysql-backup_TIMESTAMP.tar.gz      # verify
```

If GPG fails:
```bash
cat ~/.backup-encryption-key          # must not be empty
ls -la ~/.backup-encryption-key       # must be mode 600
```

### Extract

```bash
tar xzf ~/restore/mysql-backup_TIMESTAMP.tar.gz -C ~/restore/
ls ~/restore/dump_*/                  # shows available databases
```

### Restore Single Database

```bash
# ⚠ Confirm: this overwrites the existing database
mysql -u root -p <database_name> < ~/restore/dump_TIMESTAMP/<database_name>.sql
# Or using credentials file:
mysql --defaults-file=~/.mysql-backup.cnf <db_name> < ~/restore/dump_TIMESTAMP/<db>.sql
```

### Restore All Databases (Full System)

```bash
# ⚠ Confirm: this overwrites ALL databases
mysql -u root -p < ~/restore/dump_TIMESTAMP/all-databases.sql
```

### Verify

```bash
mysql -e "SHOW DATABASES;" 2>/dev/null
mysql -e "SELECT COUNT(*) FROM <db>.<key_table>;" 2>/dev/null
sudo systemctl status mysql
```

---

## App File Restore

Apps with their own backup scripts store archives in `/backups/<app>/`:

```bash
# Decrypt:
gpg --batch --passphrase-file ~/.backup-encryption-key \
    -d /backups/<app>/backup_TIMESTAMP.tar.gz.gpg \
    > /tmp/app-restore.tar.gz

# Extract and copy back:
mkdir -p /tmp/app-restore
tar xzf /tmp/app-restore.tar.gz -C /tmp/app-restore/
sudo rsync -av /tmp/app-restore/<files>/ /var/www/html/<app>/
```

---

## Restore From Local Backup (If Drive Unavailable)

```bash
ls -lth ~/backups/mysql/*.gpg | head -5    # local archives
# Same decrypt → extract → restore process above
```

---

## Cleanup

```bash
rm -rf ~/restore/ /tmp/app-restore/
# Keep .gpg archive until you confirm the restore is stable
```
```

- [ ] **Step 4: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-disaster-recovery/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-disaster-recovery/
git commit -m "feat: add linux-disaster-recovery skill"
```

---

## Task 8: linux-firewall-ssl

**Files:**
- Create: `linux-firewall-ssl/SKILL.md`
- Create: `linux-firewall-ssl/references/ssl-config.md`

- [ ] **Step 1: Create directories**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-firewall-ssl/references"
```

- [ ] **Step 2: Write SKILL.md**

Write `/c/Users/Peter/.claude/skills/linux-firewall-ssl/SKILL.md`:

```markdown
---
name: linux-firewall-ssl
description: Manage UFW firewall and SSL/TLS certificates on Ubuntu/Debian servers. UFW rule management (view, add, remove, rate limiting). Certbot operations (issue cert with --nginx plugin, check expiry, force renew, dry run, add domains, troubleshoot renewal). ECDSA certificates, TLSv1.2/1.3 only.
---
# Firewall & SSL Management

## UFW Firewall

```bash
sudo ufw status verbose                 # current rules
sudo ufw status numbered                # numbered for easy deletion

# Standard web server rule set:
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp
sudo ufw enable

# Add a rule
sudo ufw allow <port>/tcp
sudo ufw allow from <ip> to any port 22   # restrict SSH to trusted IP

# Remove a rule
sudo ufw status numbered
sudo ufw delete <number>

# Rate limiting (brute-force protection)
sudo ufw limit 22/tcp

# Logging
sudo ufw logging on
sudo tail -f /var/log/ufw.log
```

---

## SSL Certificates (Certbot)

```bash
# Issue new cert (nginx plugin — modifies config automatically)
sudo certbot --nginx -d example.com
sudo certbot --nginx -d example.com -d www.example.com

# Check all cert expiry
sudo certbot certificates

# Test auto-renewal
sudo certbot renew --dry-run

# Force renew
sudo certbot renew --force-renewal

# Add domain to existing cert
sudo certbot --nginx --expand -d existing.com -d new.com

# Check renewal timer
sudo systemctl status certbot.timer
```

---

## Troubleshoot Renewal Failure

Every HTTP server block needs this for ACME challenge:
```nginx
location /.well-known/acme-challenge/ { root /var/www/html; }
```

```bash
# Verify all vhosts have it:
sudo grep -r "acme-challenge" /etc/nginx/sites-enabled/

# Test challenge path is reachable:
curl -s http://example.com/.well-known/acme-challenge/test
# Should return 404, not connection refused

# Debug renewal:
sudo certbot renew --dry-run --debug
sudo journalctl -u certbot --no-pager | tail -30
```

Full SSL parameters and cipher config: `references/ssl-config.md`
```

- [ ] **Step 3: Write references/ssl-config.md**

Write `/c/Users/Peter/.claude/skills/linux-firewall-ssl/references/ssl-config.md`:

```markdown
# SSL Configuration Reference

## ssl-params.conf (/etc/nginx/snippets/ssl-params.conf)

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;

add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), camera=(), microphone=()" always;
```

Every SSL vhost must include:
```nginx
include snippets/ssl-params.conf;
```

Verify all SSL vhosts include it:
```bash
sudo grep -r "ssl-params" /etc/nginx/sites-enabled/
```

## Check TLS Version Quality

```bash
# Must not accept TLSv1.0 or TLSv1.1:
openssl s_client -connect <domain>:443 -tls1 2>&1 | grep -E "handshake|alert"
openssl s_client -connect <domain>:443 -tls1_1 2>&1 | grep -E "handshake|alert"
# Both should show: handshake failure

# Check what protocols are accepted:
nmap --script ssl-enum-ciphers -p 443 <domain> 2>/dev/null | grep -E "TLS|SSL"
```

## Certificate Key Type (ECDSA vs RSA)

```bash
sudo certbot certificates | grep "Certificate Path"
# Check key type:
openssl x509 -in /etc/letsencrypt/live/<domain>/cert.pem -text -noout | grep "Public Key"
```

Issue ECDSA cert (preferred):
```bash
sudo certbot --nginx -d <domain> --key-type ecdsa --elliptic-curve secp384r1
```

## phpMyAdmin SSL — Restrict + Protect

```apache
# In Apache vhost for phpMyAdmin:
<Directory /usr/share/phpmyadmin>
    AllowOverride All
    Require ip <your-trusted-ip>
    Require ip 127.0.0.1
</Directory>
```
```

- [ ] **Step 4: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-firewall-ssl/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-firewall-ssl/
git commit -m "feat: add linux-firewall-ssl skill"
```

---

## Task 9: linux-intrusion-detection

**Files:**
- Create: `linux-intrusion-detection/SKILL.md`
- Create: `linux-intrusion-detection/references/fail2ban-jails.md`

- [ ] **Step 1: Create directories**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-intrusion-detection/references"
```

- [ ] **Step 2: Write SKILL.md**

Write `/c/Users/Peter/.claude/skills/linux-intrusion-detection/SKILL.md`:

```markdown
---
name: linux-intrusion-detection
description: Manage intrusion detection on Ubuntu/Debian servers. fail2ban (check jails, unban IPs, add custom jails, tune bans, read logs). AIDE file integrity monitoring (install, initialise, run checks, schedule daily). auditd system call auditing (install, watch files, read audit log).
---
# Intrusion Detection

## fail2ban

```bash
sudo fail2ban-client status                      # all jails + count
sudo fail2ban-client status <jail>               # specific jail (bans, IPs)
sudo tail -f /var/log/fail2ban.log               # live ban activity

# Unban an IP
sudo fail2ban-client set <jail> unbanip <ip>

# Reload after config change
sudo systemctl reload fail2ban
sudo fail2ban-client status                      # verify jails loaded
```

Full jail configuration templates: `references/fail2ban-jails.md`

---

## AIDE (File Integrity Monitoring)

```bash
# Install
sudo apt install aide

# Initialise (first time — takes a few minutes)
sudo aideinit
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Run integrity check
sudo aide --check
# No output = no changes. Any output = files changed since last init.

# Update DB after intentional changes (e.g. after a deployment)
sudo aideinit
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

### Schedule Daily AIDE Check

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

```bash
sudo apt install auditd
sudo systemctl enable auditd && sudo systemctl start auditd

# Watch critical files:
sudo auditctl -w /etc/passwd -p rwxa -k passwd-changes
sudo auditctl -w /etc/shadow -p rwxa -k shadow-changes
sudo auditctl -w /etc/ssh/sshd_config -p rwxa -k ssh-config
sudo auditctl -w /var/www -p w -k webroot-writes

# Make rules permanent:
sudo nano /etc/audit/rules.d/hardening.rules
# Add the -w rules above

# Search audit log:
sudo ausearch -k passwd-changes
sudo ausearch -f /etc/passwd
sudo ausearch --start today
sudo aureport --summary
```
```

- [ ] **Step 3: Write references/fail2ban-jails.md**

Write `/c/Users/Peter/.claude/skills/linux-intrusion-detection/references/fail2ban-jails.md`:

```markdown
# fail2ban Jail Configuration Reference

## jail.local Template

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
maxretry = 6

[apache-overflows]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/error.log
maxretry = 2

[php-url-fopen]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/error.log
maxretry = 5

[recidive]
enabled  = true
logpath  = /var/log/fail2ban.log
bantime  = 604800
findtime = 86400
maxretry = 5
```

## WordPress Jails (For Sites With WordPress)

```ini
[wordpress-hard]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 2
bantime  = 86400

[wordpress-xmlrpc]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 1
bantime  = 172800
```

Requires filter files in `/etc/fail2ban/filter.d/`. Basic WordPress filter:
```ini
# /etc/fail2ban/filter.d/wordpress-hard.conf
[Definition]
failregex = ^<HOST> .* "POST .*wp-login\.php
ignoreregex =
```

## Custom SaaS API Rate Limit Jail

```ini
[saas-api-limit]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 60
findtime = 60
bantime  = 3600
filter   = saas-api-limit
```

Filter `/etc/fail2ban/filter.d/saas-api-limit.conf`:
```ini
[Definition]
failregex = ^<HOST> .* "POST /api/
ignoreregex =
```

## Operations

```bash
# Check all bans
sudo fail2ban-client status

# Unban
sudo fail2ban-client set <jail> unbanip <ip>

# Test a filter against a log file
sudo fail2ban-regex /var/log/nginx/access.log /etc/fail2ban/filter.d/saas-api-limit.conf

# Reload after changes
sudo systemctl reload fail2ban
```
```

- [ ] **Step 4: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-intrusion-detection/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-intrusion-detection/
git commit -m "feat: add linux-intrusion-detection skill (fail2ban, AIDE, auditd)"
```

---

## Task 10: linux-webstack

**Files:**
- Create: `linux-webstack/SKILL.md`
- Create: `linux-webstack/references/config-patterns.md`

- [ ] **Step 1: Create directories**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-webstack/references"
```

- [ ] **Step 2: Write SKILL.md**

Write `/c/Users/Peter/.claude/skills/linux-webstack/SKILL.md`:

```markdown
---
name: linux-webstack
description: Manage the web stack on Ubuntu/Debian servers — Nginx reverse proxy (config, reload, debug 502), Apache backend (port 8080 vhosts), PHP-FPM (pool tuning, restart), and Node.js API services (systemd). Covers the Nginx+Apache dual-stack pattern where Nginx fronts all traffic and proxies PHP apps to Apache on port 8080.
---
# Web Stack Management

```
Client → Nginx (443/80)
           ├── Astro/static → /dist/ folders
           ├── PHP direct → PHP-FPM socket
           ├── PHP apps → Apache (port 8080)
           └── Node.js APIs → localhost:<port>
```

---

## Nginx

```bash
sudo nginx -t                                      # test config (always first)
sudo nginx -t && sudo systemctl reload nginx       # graceful reload
sudo systemctl restart nginx                       # full restart

# Enable / disable site
sudo ln -s /etc/nginx/sites-available/<domain>.conf /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/<domain>.conf

sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

### Debug 502 Bad Gateway

```bash
sudo tail -20 /var/log/nginx/error.log           # what upstream is failing?
sudo systemctl status php8.3-fpm                 # PHP-FPM sites
sudo systemctl status apache2                    # Apache-proxied sites
ls -la /run/php/php8.3-fpm.sock                  # FPM socket present?
sudo systemctl restart php8.3-fpm               # fix
```

Config patterns and templates: `references/config-patterns.md`

---

## Apache (Port 8080)

```bash
sudo apache2ctl configtest                        # test config
sudo apache2ctl configtest && sudo systemctl reload apache2
sudo a2ensite <domain>.conf
sudo a2dissite <domain>.conf
sudo tail -f /var/log/apache2/error.log
```

---

## PHP-FPM

```bash
sudo php-fpm8.3 -t                               # test config
sudo systemctl reload php8.3-fpm                # graceful
sudo systemctl restart php8.3-fpm               # full restart
sudo tail -f /var/log/php8.3-fpm.log
```

### Tune Workers

```bash
sudo nano /etc/php/8.3/fpm/pool.d/www.conf
# Key settings:
# pm.max_children = 20  (RAM-dependent: (RAM_MB - 256) / avg_worker_MB)
# pm.start_servers = 4
# pm.min_spare_servers = 2
# pm.max_spare_servers = 8
# pm.max_requests = 500
sudo systemctl reload php8.3-fpm
```

---

## Node.js Services

```bash
sudo systemctl status <service-name>
sudo journalctl -u <service-name> -n 50 --no-pager
sudo systemctl restart <service-name>
```

Create new Node.js systemd unit: see `references/config-patterns.md`

---

## nginx.conf Global Settings

```bash
sudo nano /etc/nginx/nginx.conf
```
```nginx
worker_processes auto;
server_tokens off;         # hide version
client_max_body_size 64M;  # upload limit
gzip on;
```
```

- [ ] **Step 3: Write references/config-patterns.md**

Write `/c/Users/Peter/.claude/skills/linux-webstack/references/config-patterns.md`:

```markdown
# Web Stack Config Patterns

## PHP-FPM Direct (fastcgi-php.conf snippet)

```nginx
# /etc/nginx/snippets/fastcgi-php.conf
fastcgi_pass unix:/run/php/php8.3-fpm.sock;
fastcgi_index index.php;
fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
include fastcgi_params;
```

Usage in a vhost:
```nginx
location ~ \.php$ {
    include snippets/fastcgi-php.conf;
}
```

## Nginx Upstream + Node.js Proxy

```nginx
upstream myapp_api {
    server 127.0.0.1:3001;
    keepalive 32;
}

server {
    ...
    location /api/ {
        proxy_pass http://myapp_api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

## Node.js Systemd Unit Template

```ini
# /etc/systemd/system/<service-name>.service
[Unit]
Description=<App Name> API
After=network.target

[Service]
Type=simple
User=administrator
WorkingDirectory=/var/www/html/<folder>
ExecStart=/usr/bin/node <entry>.js
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=3001

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable <service-name>
sudo systemctl start <service-name>
```

## static-files.conf Snippet

```nginx
# /etc/nginx/snippets/static-files.conf
location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
    try_files $uri =404;
}
```

## Catch-All (00-default.conf) — Reject Unknown Hostnames

```nginx
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    server_name _;
    return 444;
}
```

## PHP-FPM Pool Tuning Reference

```ini
; Dynamic mode (recommended for web servers)
pm = dynamic
pm.max_children = 20        ; cap: (available_RAM_MB) / avg_worker_MB
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 8
pm.max_requests = 500       ; recycle after N requests (prevents memory leaks)
pm.process_idle_timeout = 10s
```

Typical PHP worker memory by framework:
- Plain PHP: 20-40MB
- Laravel: 50-100MB
- WordPress: 40-80MB
```

- [ ] **Step 4: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-webstack/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-webstack/
git commit -m "feat: add linux-webstack skill (Nginx, Apache, PHP-FPM, Node.js)"
```

---

## Task 11: linux-access-control

**Files:**
- Create: `linux-access-control/SKILL.md`
- Create: `linux-access-control/references/permissions-reference.md`

- [ ] **Step 1: Create directories + write files**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-access-control/references"
```

Write `/c/Users/Peter/.claude/skills/linux-access-control/SKILL.md`:

```markdown
---
name: linux-access-control
description: Manage users, groups, SSH keys, sudo access, and file permissions on Ubuntu/Debian servers. Create/delete users, manage sudo group, add/revoke SSH authorized_keys, audit who has access, fix file permissions in web roots and credential files.
---
# Access Control

## User Management

```bash
sudo adduser <username>                         # create (interactive)
sudo usermod -aG sudo <username>                # grant sudo
sudo deluser <username>                         # remove user (keeps home)
sudo deluser --remove-home <username>           # remove user + home
sudo passwd -l <username>                       # lock account
sudo passwd -u <username>                       # unlock account

# Audit
grep -v "nologin\|false" /etc/passwd | cut -d: -f1,3
grep ^sudo /etc/group                           # who has sudo
awk -F: '$3 == 0 {print $1}' /etc/passwd       # UID-0 accounts
```

---

## SSH Key Management

```bash
# Add a key for a user
mkdir -p /home/<username>/.ssh
chmod 700 /home/<username>/.ssh
echo "<public-key>" >> /home/<username>/.ssh/authorized_keys
chmod 600 /home/<username>/.ssh/authorized_keys
chown -R <username>:<username> /home/<username>/.ssh

# Audit all keys on the server
find /home /root -name authorized_keys 2>/dev/null | \
    while read f; do echo "=== $f ==="; cat "$f"; done

# Revoke: edit the file, delete the key line
sudo nano /home/<username>/.ssh/authorized_keys

# Test before restarting SSH (keep existing session open!)
sudo sshd -t && sudo systemctl restart sshd
```

---

## File Permissions — Quick Reference

```bash
# Web root standard
sudo find /var/www -type d -exec chmod 755 {} \;
sudo find /var/www -type f -exec chmod 644 {} \;
sudo chown -R www-data:www-data /var/www/html/
sudo find /var/www -type f -perm -0002 -exec chmod o-w {} \;   # remove world-write

# Critical system files
sudo chmod 640 /etc/shadow /etc/gshadow
sudo chmod 644 /etc/passwd /etc/group

# Backup credentials (must be 600)
chmod 600 ~/.mysql-backup.cnf ~/.backup-encryption-key
chmod 600 ~/.config/rclone/rclone.conf
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
```

Full permission patterns and audit commands: `references/permissions-reference.md`
```

Write `/c/Users/Peter/.claude/skills/linux-access-control/references/permissions-reference.md`:

```markdown
# Permissions Reference

## Find Permission Issues

```bash
# World-writable files in web root (should be none)
find /var/www -type f -perm -0002 2>/dev/null

# SUID/SGID binaries (unexpected ones are suspicious)
find / -perm /6000 -type f 2>/dev/null | \
    grep -vE "(sudo|passwd|su|mount|umount|ping|crontab|at|newgrp|chsh|chfn|gpasswd)"

# Unowned files
find /var/www /home /etc -nouser -nogroup 2>/dev/null

# Credential file permissions
stat -c "%a %n" ~/.mysql-backup.cnf ~/.backup-encryption-key \
    ~/.config/rclone/rclone.conf 2>/dev/null
# All must show 600
```

## Permission Reference Table

| Path | Expected Permission | Owner |
|------|--------------------|----|
| /etc/shadow | 640 | root:shadow |
| /etc/gshadow | 640 | root:shadow |
| /etc/passwd | 644 | root:root |
| /etc/group | 644 | root:root |
| /etc/ssh/sshd_config | 644 | root:root |
| ~/.ssh/ | 700 | user:user |
| ~/.ssh/authorized_keys | 600 | user:user |
| ~/.mysql-backup.cnf | 600 | user:user |
| ~/.backup-encryption-key | 600 | user:user |
| ~/.config/rclone/rclone.conf | 600 | user:user |
| /var/www directories | 755 | www-data:www-data |
| /var/www files | 644 | www-data:www-data |

## Service Account Verification

Web processes must run as www-data, not root:

```bash
ps aux | grep "nginx: worker" | grep -v grep     # must show www-data
ps aux | grep "php-fpm" | grep "pool" | grep -v grep  # must show www-data

# nginx.conf:
grep "^user" /etc/nginx/nginx.conf               # user www-data;

# php-fpm pool:
grep "^user\|^group" /etc/php/8.3/fpm/pool.d/www.conf
```
```

- [ ] **Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-access-control/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-access-control/
git commit -m "feat: add linux-access-control skill"
```

---

## Task 12: linux-system-monitoring

**Files:**
- Create: `linux-system-monitoring/SKILL.md`
- Create: `linux-system-monitoring/references/monitoring-commands.md`

- [ ] **Step 1: Create directories + write files**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-system-monitoring/references"
```

Write `/c/Users/Peter/.claude/skills/linux-system-monitoring/SKILL.md`:

```markdown
---
name: linux-system-monitoring
description: Monitor system health on Ubuntu/Debian production servers. CPU load, memory, disk I/O, network connections, process inspection. Covers htop, iostat, vmstat, ss, and backup health verification. Includes what warning signs to watch for. Reference-style — outputs commands and how to read them.
---
# System Monitoring

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
```

Write `/c/Users/Peter/.claude/skills/linux-system-monitoring/references/monitoring-commands.md`:

```markdown
# Monitoring Commands Reference

## vmstat

```bash
vmstat 1 10
# Columns: r=run queue, b=blocked, si/so=swap(should be 0), wa=I/O wait
# r > nproc = CPU bottleneck | wa > 20% = disk bottleneck
```

## iostat Interpretation

```bash
iostat -x 1 5
# %util > 80% sustained = disk bottleneck
# await > 50ms = slow disk response
# r/s + w/s = operations per second
```

## Memory Deep Dive

```bash
cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable|Cached|Buffers|SwapTotal"
# MemAvailable = truly free for new processes (not just MemFree)

# Per-process memory
ps aux --sort=-%mem | awk 'NR<=11{printf "%-30s %s MB\n", $11, $6/1024}'
```

## Network Connection Analysis

```bash
# Connections by state
ss -tan | awk '{print $1}' | sort | uniq -c | sort -rn
# ESTABLISHED = active | TIME_WAIT = closing | CLOSE_WAIT = may leak

# Connections per IP to web ports
ss -tan 'sport = :443 or sport = :80' | awk '{print $5}' | \
    cut -d: -f1 | sort | uniq -c | sort -rn | head -10

# Open file descriptors per service
ls -l /proc/$(pgrep -f nginx | head -1)/fd 2>/dev/null | wc -l
```

## Per-Service Resource Usage

```bash
# Memory and CPU from systemd
for s in nginx apache2 mysql postgresql php8.3-fpm fail2ban; do
    mem=$(systemctl show $s --property=MemoryCurrent 2>/dev/null | \
          cut -d= -f2)
    echo "$s: $((${mem:-0}/1024/1024)) MB"
done

# Or via ps:
ps aux | grep -E "nginx|mysql|php-fpm|apache" | \
    awk '{sum[$11]+=$6} END {for(p in sum) printf "%s %s MB\n", sum[p]/1024, p}' | \
    sort -rn
```

## Disk Space Trend

```bash
df -h                              # current
du -sh /var/log/ /var/www/ ~/backups/  # top consumers
sudo find / -type f -size +500M 2>/dev/null   # very large files
```
```

- [ ] **Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-system-monitoring/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-system-monitoring/
git commit -m "feat: add linux-system-monitoring skill"
```

---

## Task 13: linux-disk-storage

**Files:**
- Create: `linux-disk-storage/SKILL.md`
- Create: `linux-disk-storage/references/storage-reference.md`

- [ ] **Step 1: Create directories + write files**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-disk-storage/references"
```

Write `/c/Users/Peter/.claude/skills/linux-disk-storage/SKILL.md`:

```markdown
---
name: linux-disk-storage
description: Manage disk space on Ubuntu/Debian servers. Check usage, find space hogs, safe cleanup (apt cache, journal, old logs, old backups, node_modules), inode exhaustion, and emergency disk-full recovery. Includes swapfile creation for servers running without swap.
---
# Disk & Storage

## Check Usage

```bash
df -h                           # filesystem overview (concern: > 85% used)
df -i                           # inode usage (can be full independently)
du -sh /var/www/* | sort -rh | head -10
du -sh /var/log/* 2>/dev/null | sort -rh | head -10
du -sh ~/backups/* 2>/dev/null | sort -rh | head -5
sudo find / -type f -size +100M 2>/dev/null | head -10
```

---

## Safe Cleanup (In Order Of Safety)

```bash
# 1. APT cache (always safe)
sudo apt clean && sudo apt autoremove

# 2. Journal logs (safe, keeps recent 14 days)
sudo journalctl --vacuum-time=14d
sudo journalctl --vacuum-size=500M

# 3. Old backup files (verify retention script is running first)
find ~/backups/mysql/ -name "*.gpg" -mtime +7 -delete

# 4. Temp files
sudo find /tmp /var/tmp -type f -mtime +7 -delete

# 5. node_modules after successful Astro build
# cd /var/www[/html]/<site> && rm -rf node_modules
# (update-all-repos will reinstall on next pull)
```

---

## Emergency Disk Full

```bash
# Fast identification
df -h && du -sh /var/www/* /var/log/* ~/backups/* 2>/dev/null | sort -rh | head -10

# Immediate wins (safe):
sudo apt clean
sudo journalctl --vacuum-size=200M
sudo find /tmp /var/tmp -type f -mtime +7 -delete

# Truncate an oversize log (safer than deleting):
sudo truncate -s 0 /var/log/<oversize-log-file>
```

---

## Inode Exhaustion (df -i shows 100%)

```bash
# Find dir with most files:
sudo find / -xdev -type f 2>/dev/null | cut -d/ -f2 | sort | uniq -c | sort -rn | head

# Common causes: PHP sessions, mail spool, tiny cache files
sudo find /var/lib/php/sessions/ -type f | wc -l
sudo find /tmp -type f | wc -l
```

---

## Swapfile (Safety Net For No-Swap Servers)

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.d/99-swappiness.conf
sudo sysctl vm.swappiness=10
free -h                   # verify Swap shows 2G
```

Full cleanup targets and LVM reference: `references/storage-reference.md`
```

Write `/c/Users/Peter/.claude/skills/linux-disk-storage/references/storage-reference.md`:

```markdown
# Storage Reference

## Cleanup Targets (Priority Order)

| Target | Safe? | Command |
|--------|-------|---------|
| APT cache | Always | `sudo apt clean && sudo apt autoremove` |
| Journal (old) | Yes | `sudo journalctl --vacuum-time=14d` |
| Temp files (old) | Yes | `find /tmp -mtime +7 -delete` |
| Old backup .gpg | Yes if >7d | `find ~/backups -name "*.gpg" -mtime +7 -delete` |
| node_modules | Yes after build | `rm -rf <site>/node_modules` |
| Core dumps | Yes | `sudo find / -name "core" -type f -delete` |
| Old kernel images | Check first | `sudo apt autoremove` |

## Disk Usage Commands

```bash
# Sorted by size, human-readable
du -sh /var/www/* | sort -rh
du -sh /var/log/* 2>/dev/null | sort -rh
du -sh /* 2>/dev/null | sort -rh | head -15

# Find files larger than X:
find / -type f -size +500M 2>/dev/null
find / -type f -size +100M 2>/dev/null | grep -v proc

# Files modified recently (last 24h) — find what changed:
find / -type f -newer /tmp/.ts 2>/dev/null
# (touch /tmp/.ts first to set the reference time)
```

## logrotate Config Template

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

## LVM Basics (If Server Uses LVM)

```bash
# Check if LVM is in use:
sudo pvs 2>/dev/null     # physical volumes
sudo vgs 2>/dev/null     # volume groups
sudo lvs 2>/dev/null     # logical volumes

# Extend a logical volume (if VG has free space):
sudo lvextend -L +10G /dev/<vg>/<lv>
sudo resize2fs /dev/<vg>/<lv>     # ext4
# or: sudo xfs_growfs /dev/<vg>/<lv>  # xfs
```
```

- [ ] **Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-disk-storage/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-disk-storage/
git commit -m "feat: add linux-disk-storage skill"
```

---

## Task 14: linux-log-management

**Files:**
- Create: `linux-log-management/SKILL.md`
- Create: `linux-log-management/references/log-locations.md`

- [ ] **Step 1: Create directories + write files**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-log-management/references"
```

Write `/c/Users/Peter/.claude/skills/linux-log-management/SKILL.md`:

```markdown
---
name: linux-log-management
description: Read and manage logs on Ubuntu/Debian servers. journalctl by service/time/priority. Nginx and Apache log analysis (4xx/5xx spikes, attack patterns, top IPs). fail2ban ban log. MySQL slow queries. PHP errors. Backup cron log. logrotate management. Reference-style with ready-to-run commands.
---
# Log Management

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
```

Write `/c/Users/Peter/.claude/skills/linux-log-management/references/log-locations.md`:

```markdown
# Log File Locations

## System Logs

| Log | Location | View Command |
|-----|----------|-------------|
| systemd journal | `journalctl` | `sudo journalctl -u <service>` |
| kernel messages | `journalctl -k` | `sudo dmesg` |
| auth/sudo | `/var/log/auth.log` | `sudo tail -f /var/log/auth.log` |
| syslog | `/var/log/syslog` | `sudo tail -f /var/log/syslog` |

## Web Server Logs

| Log | Location |
|-----|----------|
| Nginx access | `/var/log/nginx/access.log` |
| Nginx error | `/var/log/nginx/error.log` |
| Nginx per-domain | `/var/log/nginx/<domain>-*.log` (if configured) |
| Apache error | `/var/log/apache2/error.log` |
| Apache access | `/var/log/apache2/access.log` |
| Apache per-domain | `/var/log/apache2/<domain>-*.log` |

## Application Logs

| Log | Location |
|-----|----------|
| PHP-FPM | `/var/log/php8.3-fpm.log` |
| PHP errors | `/var/log/php_errors.log` or per app.ini |
| MySQL error | `/var/log/mysql/error.log` |
| MySQL slow query | `/var/log/mysql/mysql-slow.log` |
| PostgreSQL | `/var/log/postgresql/postgresql-*.log` |
| Redis | `/var/log/redis/redis-server.log` |

## Security Logs

| Log | Location |
|-----|----------|
| fail2ban | `/var/log/fail2ban.log` |
| UFW | `/var/log/ufw.log` |
| auditd | `/var/log/audit/audit.log` |

## Backup Logs

| Log | Location |
|-----|----------|
| MySQL backup cron | `~/backups/mysql/cron.log` |
| App backup cron | `/backups/<app>/cron.log` |

## logrotate Configs

```bash
ls /etc/logrotate.d/      # all rotation configs
cat /etc/logrotate.conf   # global defaults
```

Force rotation for a service:
```bash
sudo logrotate -f /etc/logrotate.d/<service>
sudo logrotate -f /etc/logrotate.d/nginx
```

Add a new log to rotation: copy the template from `linux-disk-storage`
references/storage-reference.md logrotate section.
```

- [ ] **Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-log-management/SKILL.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-log-management/
git commit -m "feat: add linux-log-management skill"
```

---

## Task 15: linux-server-provisioning

**Files:**
- Create: `linux-server-provisioning/SKILL.md`
- Create: `linux-server-provisioning/references/provisioning-steps.md`

- [ ] **Step 1: Create directories**

```bash
mkdir -p "/c/Users/Peter/.claude/skills/linux-server-provisioning/references"
```

- [ ] **Step 2: Write SKILL.md**

Write `/c/Users/Peter/.claude/skills/linux-server-provisioning/SKILL.md`:

```markdown
---
name: linux-server-provisioning
description: Set up a fresh Ubuntu/Debian server from scratch for production web hosting. Interactive step-by-step. Covers hostname, timezone, admin user, SSH hardening, UFW, full stack installation (Nginx, Apache port 8080, PHP-FPM, MySQL 8, PostgreSQL, Redis, Node.js, fail2ban, certbot, rclone, msmtp), Nginx snippet setup, and post-install security verification.
---
# Server Provisioning

Sets up a fresh server. Ask first:
1. **Hostname?**
2. **Timezone?** (default: Africa/Nairobi)
3. **Which stack?** (confirm: Nginx + Apache + PHP8.3 + MySQL + PostgreSQL + Redis)

Work through sections in order. Full commands: `references/provisioning-steps.md`

---

## Section Overview

| # | Section | Est. time |
|---|---------|-----------|
| 1 | System update + hostname + timezone | 5 min |
| 2 | Admin user + sudo | 2 min |
| 3 | SSH hardening | 5 min |
| 4 | UFW firewall | 2 min |
| 5 | Automatic security updates | 2 min |
| 6 | Web stack (Nginx, Apache, PHP-FPM) | 10 min |
| 7 | Databases (MySQL, PostgreSQL, Redis) | 10 min |
| 8 | Supporting tools (fail2ban, certbot, rclone, msmtp, Node.js) | 10 min |
| 9 | Nginx snippets + catch-all config | 10 min |
| 10 | Clone linux-skills + symlink scripts | 5 min |
| 11 | Post-install security check | 5 min |

---

## Critical Steps (Do Not Skip)

```bash
# After SSH hardening — ALWAYS test in a second terminal before closing first:
ssh administrator@<server-ip>

# After Apache port change — verify it's on 8080 not 80:
ss -tlnp | grep apache

# After MySQL install — bind to localhost:
grep bind-address /etc/mysql/mysql.conf.d/mysqld.cnf

# Final check:
sudo check-server-security
```

---

## Quick Reference

```bash
# Test Nginx config
sudo nginx -t && sudo systemctl reload nginx

# All services should be active after provisioning:
for s in nginx apache2 mysql postgresql php8.3-fpm redis fail2ban; do
    printf "%-20s %s\n" $s "$(systemctl is-active $s)"
done

# Verify firewall
sudo ufw status verbose
```

Full step-by-step installation commands: `references/provisioning-steps.md`
Next step after provisioning: `linux-server-hardening`
```

- [ ] **Step 3: Write references/provisioning-steps.md**

Write `/c/Users/Peter/.claude/skills/linux-server-provisioning/references/provisioning-steps.md`:

```markdown
# Provisioning Steps — Full Commands

## 1. System Update & Base Config

```bash
sudo apt update && sudo apt upgrade -y
sudo hostnamectl set-hostname <server-name>
echo "127.0.1.1 <server-name>" | sudo tee -a /etc/hosts
sudo timedatectl set-timezone Africa/Nairobi
timedatectl
sudo locale-gen en_GB.UTF-8 && sudo update-locale LANG=en_GB.UTF-8
```

## 2. Admin User

```bash
sudo adduser administrator
sudo usermod -aG sudo administrator
# If provisioning from root, copy SSH key:
sudo mkdir -p /home/administrator/.ssh
sudo cp /root/.ssh/authorized_keys /home/administrator/.ssh/
sudo chown -R administrator:administrator /home/administrator/.ssh
sudo chmod 700 /home/administrator/.ssh
sudo chmod 600 /home/administrator/.ssh/authorized_keys
# TEST LOGIN IN NEW TERMINAL BEFORE CONTINUING
```

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
# VERIFY LOGIN IN SECOND TERMINAL FIRST
```

## 4. UFW

```bash
sudo ufw default deny incoming && sudo ufw default allow outgoing
sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp
sudo ufw enable && sudo ufw status verbose
```

## 5. Automatic Updates

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure unattended-upgrades    # select Yes
```

## 6. Web Stack

```bash
# Nginx
sudo apt install -y nginx
sudo systemctl enable nginx

# Apache on port 8080
sudo apt install -y apache2
sudo nano /etc/apache2/ports.conf
# Change: Listen 80 → Listen 8080
sudo nano /etc/apache2/sites-available/000-default.conf
# Change: <VirtualHost *:80> → <VirtualHost *:8080>
sudo systemctl enable apache2 && sudo systemctl restart apache2
ss -tlnp | grep apache   # verify: 0.0.0.0:8080

# PHP 8.3
sudo apt install -y php8.3-fpm php8.3-cli php8.3-mysql php8.3-pgsql \
    php8.3-curl php8.3-mbstring php8.3-xml php8.3-zip php8.3-gd \
    php8.3-redis php8.3-intl php8.3-bcmath
sudo systemctl enable php8.3-fpm
```

## 7. Databases

```bash
# MySQL 8
sudo apt install -y mysql-server
sudo systemctl enable mysql
sudo mysql_secure_installation
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
# Set: bind-address = 127.0.0.1
sudo systemctl restart mysql
ss -tlnp | grep 3306   # must show 127.0.0.1:3306

# PostgreSQL
sudo apt install -y postgresql postgresql-contrib
sudo systemctl enable postgresql

# Redis
sudo apt install -y redis-server
sudo systemctl enable redis
sudo nano /etc/redis/redis.conf
# Ensure: bind 127.0.0.1 -::1 | Set: requirepass <strong-password>
sudo systemctl restart redis
ss -tlnp | grep 6379   # must show 127.0.0.1:6379
```

## 8. Supporting Tools

```bash
# Node.js LTS
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs

# fail2ban
sudo apt install -y fail2ban && sudo systemctl enable fail2ban

# Certbot (nginx + apache plugins)
sudo apt install -y certbot python3-certbot-nginx python3-certbot-apache

# rclone
curl https://rclone.org/install.sh | sudo bash

# msmtp
sudo apt install -y msmtp msmtp-mta
```

## 9. Nginx Snippets & Catch-All

```bash
sudo mkdir -p /etc/nginx/snippets

# security-dotfiles.conf
cat << 'EOF' | sudo tee /etc/nginx/snippets/security-dotfiles.conf
location ~ /\. { deny all; return 404; }
location ~* \.(env|git|sql|bak|htpasswd|config)$ { deny all; return 404; }
EOF

# ssl-params.conf
cat << 'EOF' | sudo tee /etc/nginx/snippets/ssl-params.conf
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_stapling on;
ssl_stapling_verify on;
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
EOF

# proxy-to-apache.conf
cat << 'EOF' | sudo tee /etc/nginx/snippets/proxy-to-apache.conf
proxy_pass http://127.0.0.1:8080;
proxy_http_version 1.1;
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
EOF

# Catch-all (rejects unknown hostnames)
cat << 'EOF' | sudo tee /etc/nginx/sites-available/00-default.conf
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl default_server;
    ssl_certificate /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    server_name _;
    return 444;
}
EOF

sudo ln -s /etc/nginx/sites-available/00-default.conf /etc/nginx/sites-enabled/
sudo nano /etc/nginx/nginx.conf   # add: server_tokens off;
sudo nginx -t && sudo systemctl reload nginx
```

## 10. Clone Linux Skills & Scripts

```bash
cd /home/administrator
git clone <linux-skills-repo-url> linux-skills

sudo ln -sf /home/administrator/linux-skills/scripts/server-audit.sh \
    /usr/local/bin/check-server-security
sudo chmod +x /usr/local/bin/check-server-security

sudo cp /home/administrator/linux-skills/scripts/update-all-repos \
    /usr/local/bin/update-all-repos
sudo chmod +x /usr/local/bin/update-all-repos
printf '#!/bin/bash\n/usr/local/bin/update-all-repos "$@"\n' | \
    sudo tee /usr/local/bin/update-repos
sudo chmod +x /usr/local/bin/update-repos
```

## 11. Post-Install Security Check

```bash
sudo check-server-security
# Fix all FAIL items before going to production
# Then run: linux-server-hardening
```
```

- [ ] **Step 4: Verify + Commit**

```bash
wc -l "/c/Users/Peter/.claude/skills/linux-server-provisioning/SKILL.md"
wc -l "/c/Users/Peter/.claude/skills/linux-server-provisioning/references/provisioning-steps.md"
cd "/c/Users/Peter/.claude/skills"
git add linux-server-provisioning/
git commit -m "feat: add linux-server-provisioning skill"
```

---

## Self-Review

### Spec Coverage

| Requirement | Task |
|---|---|
| Hub + 14-option menu + routing | Task 1 |
| 10-layer security analysis + severity report | Task 2 |
| Interactive hardening walkthrough | Task 3 |
| Site deployment — 3 patterns, 8 steps, Nginx templates | Task 4 |
| All services: start/stop/logs/diagnose | Task 5 |
| 10 troubleshooting branches | Task 6 |
| GPG decrypt + MySQL restore + app file restore | Task 7 |
| UFW + certbot + ssl-params + renewal troubleshooting | Task 8 |
| fail2ban jails + AIDE + auditd | Task 9 |
| Nginx + Apache + PHP-FPM + Node.js patterns | Task 10 |
| Users + SSH keys + file permissions | Task 11 |
| CPU + memory + disk I/O + network monitoring | Task 12 |
| Disk cleanup + emergency recovery + swapfile | Task 13 |
| journalctl + all log files + logrotate + attack patterns | Task 14 |
| Fresh server A→Z (all services + snippets + scripts) | Task 15 |

All spec requirements covered.

### Placeholder Scan

No TBD, TODO, or vague instructions. All tasks contain actual commands and real file content.

### Structure Check

All 15 skills follow the two-tier structure:
- `SKILL.md` ≤ 500 lines — orchestration + key commands
- `references/*.md` — deep-dive content, expandable with book knowledge

---

*Plan written: 2026-04-09*
*Spec: docs/superpowers/specs/2026-04-09-linux-server-skills-design.md*
*Skills destination: C:\Users\Peter\.claude\skills\*
