# Server Security Hardening — Debian / Ubuntu

Complete guide for auditing and hardening a production Debian/Ubuntu web server.
Balances **security**, **performance**, and **service delivery** — performance is paramount.

**Philosophy:** Security is a process, not a one-time task. The goal is to raise the cost
of attack so high that automated bots move on and targeted attackers face serious obstacles —
without breaking the services your users depend on.

---

## Table of Contents

1. [Quick Start — Run the Audit](#1-quick-start--run-the-audit)
2. [System Updates](#2-system-updates)
3. [SSH Hardening](#3-ssh-hardening)
4. [Firewall (UFW)](#4-firewall-ufw)
5. [Fail2Ban — Intrusion Prevention](#5-fail2ban--intrusion-prevention)
6. [Kernel Hardening (sysctl)](#6-kernel-hardening-sysctl)
7. [MySQL / MariaDB Security](#7-mysql--mariadb-security)
8. [Apache Security](#8-apache-security)
9. [PHP Security](#9-php-security)
10. [SSL/TLS Certificates](#10-ssltls-certificates)
11. [phpMyAdmin Hardening](#11-phpmyadmin-hardening)
12. [Redis Security](#12-redis-security)
13. [File Permissions](#13-file-permissions)
14. [Backups (Your Last Line of Defense)](#14-backups-your-last-line-of-defense)
15. [Optional — Going Further](#15-optional--going-further)
16. [Maintenance Schedule](#16-maintenance-schedule)

---

## 1. Quick Start — Run the Audit

The `server-audit.sh` script checks everything in this guide non-destructively.

```bash
# Symlink to make it available as a command
sudo ln -s /home/administrator/linux-skills/scripts/server-audit.sh /usr/local/bin/check-server-security

# Run it
sudo check-server-security
```

It outputs color-coded **PASS** / **WARN** / **FAIL** for each check with a final score.
Fix FAIL items first, then work through WARNs.

---

## 2. System Updates

Unpatched software is the #1 attack vector. Automatic security updates are non-negotiable.

### Install & Enable

```bash
sudo apt install unattended-upgrades
sudo dpkg-reconfigure unattended-upgrades   # Select "Yes"
```

### Verify

```bash
cat /etc/apt/apt.conf.d/20auto-upgrades
# Should show:
# APT::Periodic::Update-Package-Lists "1";
# APT::Periodic::Unattended-Upgrade "1";
```

### Manual update when needed

```bash
sudo apt update && sudo apt upgrade
```

---

## 3. SSH Hardening

SSH is the front door. Lock it down without locking yourself out.

### 3.1 Key-Only Authentication (recommended)

**On your local machine** (if you don't already have a key):
```bash
ssh-keygen -t ed25519 -a 100
```

**Copy to server:**
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub user@server
```

**Test key login works before disabling passwords!**

### 3.2 Harden sshd_config

Create a drop-in config (survives package upgrades):

```bash
sudo nano /etc/ssh/sshd_config.d/99-hardening.conf
```

```
# 2025-XX-XX server security hardening
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
# Test config before restarting (critical — bad config = locked out!)
sudo sshd -t && sudo systemctl restart sshd
```

**WARNING:** Always keep an existing SSH session open while testing changes.
Open a second terminal and verify you can still log in before closing the first.

---

## 4. Firewall (UFW)

Default deny + whitelist only what's needed.

### Enable with basic rules

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
```

### Verify

```bash
sudo ufw status verbose
```

### Key points
- MySQL (3306), Redis (6379), PostgreSQL (5432) should **never** be in UFW allow rules
  — they should only be on localhost
- If you change the SSH port, update the rule **before** restarting sshd

---

## 5. Fail2Ban — Intrusion Prevention

Automatically bans IPs that show malicious behavior.

### Install

```bash
sudo apt install fail2ban
```

### Configure

Create `/etc/fail2ban/jail.local` (do not edit `jail.conf` — it gets overwritten on updates):

```ini
[DEFAULT]
bantime = 86400
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

# ===== SSH =====
[sshd]
enabled = true
port = ssh
maxretry = 4
bantime = 3600

# ===== Apache =====
[apache-auth]
enabled = true
port = http,https
logpath = /var/log/apache2/error.log
maxretry = 5
bantime = 1800

[apache-badbots]
enabled = true
port = http,https
logpath = /var/log/apache2/access.log
bantime = 172800

[apache-noscript]
enabled = true
port = http,https
logpath = /var/log/apache2/access.log
maxretry = 6

[apache-shellshock]
enabled = true
port = http,https
logpath = /var/log/apache2/access.log
maxretry = 1
bantime = 86400

# ===== PHP =====
[php-url-fopen]
enabled = true
port = http,https
logpath = /var/log/apache2/error.log
maxretry = 5

# ===== Rate Limiting =====
[apache-limit-request]
enabled = true
port = http,https
logpath = /var/log/apache2/error.log
maxretry = 3

# ===== Repeat Offenders =====
[recidive]
enabled = true
logpath = /var/log/fail2ban.log
bantime = 604800
findtime = 86400
maxretry = 5
```

```bash
sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
sudo fail2ban-client status
```

---

## 6. Kernel Hardening (sysctl)

Network stack and kernel security parameters. These have **zero performance impact**
on normal web server workloads.

### Create hardening config

```bash
sudo nano /etc/sysctl.d/99-security.conf
```

```ini
# === Network Security ===
# Enable SYN cookies (DDoS protection)
net.ipv4.tcp_syncookies = 1

# Disable ICMP redirects (prevent MITM routing attacks)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Enable reverse path filtering (prevent IP spoofing)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Log martian packets (packets with impossible addresses)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore ICMP broadcast requests (prevent Smurf attacks)
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP error responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# === Kernel Security ===
# Full ASLR
kernel.randomize_va_space = 2

# Restrict kernel log access
kernel.dmesg_restrict = 1

# Restrict kernel pointer exposure
kernel.kptr_restrict = 2

# Disable SysRq (prevent console-level attacks)
kernel.sysrq = 0
```

```bash
sudo sysctl --system   # Apply all sysctl configs
```

### Verify

```bash
sudo sysctl net.ipv4.conf.all.rp_filter   # Should be 1
sudo sysctl net.ipv4.conf.all.send_redirects   # Should be 0
```

---

## 7. MySQL / MariaDB Security

### 7.1 Bind to localhost

**This is critical.** If MySQL is on `*:3306`, anyone on the internet can try to connect.

Find the config file:
```bash
# MySQL
sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf

# MariaDB
sudo nano /etc/mysql/mariadb.conf.d/50-server.cnf
```

Set or verify:
```ini
[mysqld]
bind-address = 127.0.0.1
mysqlx-bind-address = 127.0.0.1
# Or disable X Protocol entirely if not used:
# mysqlx = 0
```

```bash
sudo systemctl restart mysql
# Verify
ss -tlnp | grep 3306   # Should show 127.0.0.1:3306, NOT *:3306
```

### 7.2 Remove test databases and anonymous users

```bash
sudo mysql_secure_installation
```

This will prompt to:
- Set/change root password
- Remove anonymous users
- Disallow remote root login
- Remove test database

### 7.3 Application database users

Each application should have its own MySQL user with **only** the permissions it needs:

```sql
-- Example: create a user for the 'appname' database only
CREATE USER 'appuser'@'localhost' IDENTIFIED BY 'strong-random-password';
GRANT SELECT, INSERT, UPDATE, DELETE ON appname.* TO 'appuser'@'localhost';
FLUSH PRIVILEGES;
```

Never use `root` for application connections.

---

## 8. Apache Security

### 8.1 Hide server information

Edit `/etc/apache2/conf-available/security.conf`:

```apache
# Don't reveal Apache version or OS
ServerTokens Prod
ServerSignature Off
```

```bash
sudo systemctl reload apache2
```

### 8.2 Security headers (apply to ALL vhosts)

Add to each SSL vhost config, inside the `<VirtualHost *:443>` block:

```apache
# Security headers
Header always set X-Content-Type-Options "nosniff"
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-XSS-Protection "1; mode=block"
Header always set Referrer-Policy "strict-origin-when-cross-origin"
Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
Header always set Permissions-Policy "geolocation=(), camera=(), microphone=()"
```

Or add them globally in `/etc/apache2/conf-available/security.conf` to apply everywhere.

### 8.3 Disable directory listing

```apache
<Directory /var/www/>
    Options -Indexes +FollowSymLinks
</Directory>
```

### 8.4 Enable required modules

```bash
sudo a2enmod headers ssl rewrite
sudo systemctl reload apache2
```

---

## 9. PHP Security

Edit the PHP ini for Apache (the CLI ini is separate and less critical):

```bash
# Find the right ini file
php --ini | grep "Loaded Configuration"
# Usually: /etc/php/8.x/apache2/php.ini
sudo nano /etc/php/8.4/apache2/php.ini
```

### Recommended settings

```ini
; Don't advertise PHP version in HTTP headers
expose_php = Off

; Never display errors to users in production
display_errors = Off
log_errors = On
error_log = /var/log/php_errors.log

; Prevent remote file inclusion attacks
allow_url_include = Off

; Session security
session.cookie_httponly = 1
session.cookie_secure = 1
session.use_strict_mode = 1
session.cookie_samesite = Lax

; Disable dangerous functions not needed by your apps
; NOTE: Test with your applications first! Some frameworks need exec/proc_open.
; Start conservative and remove functions your apps actually need.
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,parse_ini_file,show_source

; Upload limits (adjust to your needs)
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 120
memory_limit = 256M
```

**IMPORTANT:** The `disable_functions` list needs testing. Laravel, for example, uses
`proc_open` for Artisan commands and queue workers. Remove functions from the disabled
list that your applications legitimately need.

```bash
sudo systemctl restart apache2
```

### Verify

```bash
# Check a specific setting
php -r "echo ini_get('expose_php');"   # Should be empty/0
```

---

## 10. SSL/TLS Certificates

### Let's Encrypt with auto-renewal

```bash
sudo apt install certbot python3-certbot-apache
```

### Issue certificates

```bash
sudo certbot --apache -d yourdomain.com -d www.yourdomain.com
```

### Verify auto-renewal

```bash
sudo certbot renew --dry-run
sudo systemctl status certbot.timer
```

### Force renewal if expiring soon

```bash
sudo certbot renew --force-renewal
```

---

## 11. phpMyAdmin Hardening

phpMyAdmin is a high-value target — it's a direct gateway to your databases.

### 11.1 Production Server Banner

Customize the login page to show which server you're on (prevents accidental
operations on the wrong server).

**Files to modify:**

1. `templates/login/header.twig` — Add a banner after the `<h1>` tag:

```twig
<div style="background-color: #dc3545; color: #fff; border: 3px solid #a71d2a;
     border-radius: 8px; padding: 15px 20px; margin: 15px 0 20px 0;
     text-align: center; font-size: 16px;">
  <div style="font-size: 13px; font-weight: bold; text-transform: uppercase;
       letter-spacing: 2px; margin-bottom: 6px; background: #a71d2a;
       display: inline-block; padding: 2px 12px; border-radius: 3px;">
    &#9888; PRODUCTION SERVER &#9888;
  </div>
  <div style="font-size: 22px; font-weight: bold; margin: 6px 0;">{{ server_hostname }}</div>
  <div style="font-size: 18px; font-family: monospace;">{{ server_ip }}</div>
</div>
```

2. `libraries/classes/Plugins/Auth/AuthenticationCookie.php` — Pass hostname/IP
   to the template by adding before the login header render:

```php
$serverHostname = gethostname() ?: 'Unknown';
$serverIp = trim(shell_exec("hostname -I 2>/dev/null | awk '{print \\$1}'") ?: '');
if (empty($serverIp)) {
    $serverIp = $_SERVER['SERVER_ADDR'] ?? '';
}
```

Then add `'server_hostname' => $serverHostname, 'server_ip' => $serverIp,` to both
template render arrays.

**Color guide for different environments:**
| Environment | Background | Border     |
|-------------|-----------|------------|
| Production  | `#dc3545` | `#a71d2a`  |
| Staging     | `#ffc107` | `#d4a106`  |
| Development | `#28a745` | `#1e7e34`  |

### 11.2 IP Restriction (recommended)

Restrict phpMyAdmin access to your IP only:

```apache
# In the phpMyAdmin vhost config
<Directory /var/www/html/phpmyadmin>
    AllowOverride All
    Require ip YOUR.TRUSTED.IP.ADDRESS
    Require ip 127.0.0.1
</Directory>
```

### 11.3 Additional hardening

- Set a strong `blowfish_secret` (32+ characters) in `config.inc.php`
- Disable root login via phpMyAdmin (use app-specific accounts)
- Keep phpMyAdmin updated

---

## 12. Redis Security

Redis should **never** be exposed to the network.

### Verify localhost binding

```bash
grep "^bind" /etc/redis/redis.conf
# Should be: bind 127.0.0.1 -::1
```

### Set a password (if not already)

```bash
sudo nano /etc/redis/redis.conf
```

```
requirepass your-strong-redis-password
```

### Disable dangerous commands

```
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command CONFIG ""
rename-command DEBUG ""
```

### Verify

```bash
ss -tlnp | grep 6379   # Should show 127.0.0.1:6379 only
```

---

## 13. File Permissions

### Critical system files

```bash
sudo chmod 640 /etc/shadow /etc/gshadow
sudo chmod 644 /etc/passwd /etc/group
```

### Web root

```bash
# No world-writable files
sudo find /var/www -type f -perm -0002 -exec chmod o-w {} \;

# Web files owned by www-data
sudo chown -R www-data:www-data /var/www/html/

# Directories: 755, Files: 644
sudo find /var/www -type d -exec chmod 755 {} \;
sudo find /var/www -type f -exec chmod 644 {} \;
```

### Credential files

```bash
# MySQL backup credentials
chmod 600 ~/.mysql-backup.cnf

# SSH keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

---

## 14. Backups (Your Last Line of Defense)

If everything else fails, backups save you. Already covered in `notes/mysql-backup-setup.md`.

Key points:
- Automated MySQL backups every 3 hours via cron
- Uploaded to Google Drive via rclone
- 7-day local retention, 3-day remote retention
- Test restores periodically!

### Verify backups are running

```bash
# Check cron
crontab -l | grep backup

# Check recent backups
ls -la ~/backups/mysql/ | tail -5

# Check Google Drive
rclone ls gdrive:mysql-backups/ | tail -5
```

---

## 15. Optional — Going Further

These provide additional layers but are not essential for most setups:

### 15.1 AIDE (File Integrity Monitoring)

Detects unauthorized changes to system files.

```bash
sudo apt install aide
sudo aideinit              # Creates initial database (takes a few minutes)
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

Add to cron for daily checks:
```bash
# /etc/cron.daily/aide-check
sudo aide --check | mail -s "AIDE Report $(hostname)" admin@example.com
```

### 15.2 Logwatch

Daily email summaries of system logs.

```bash
sudo apt install logwatch
sudo logwatch --detail high --output stdout --range yesterday
```

### 15.3 Audit daemon

Track specific file access and system calls.

```bash
sudo apt install auditd
sudo systemctl enable auditd
```

### 15.4 Lynis — Security Scanner

```bash
sudo apt install lynis
sudo lynis audit system
```

Produces a detailed report with a hardening index and specific recommendations.

---

## 16. Maintenance Schedule

| Frequency    | Task                                           |
|-------------|------------------------------------------------|
| Daily       | Check fail2ban bans (automated via email)      |
| Weekly      | Run `sudo server-audit` and review output      |
| Weekly      | Check backup integrity                         |
| Monthly     | Review user accounts and SSH keys              |
| Monthly     | Check SSL certificate expiry dates             |
| Quarterly   | Run `sudo lynis audit system` (if installed)   |
| Quarterly   | Review and update fail2ban rules               |
| On change   | Re-run audit after any server config change    |

---

## Quick Reference — What to Fix First

**Priority 1 (FAIL items — fix immediately):**
- MySQL/Redis/PostgreSQL listening on all interfaces
- No firewall enabled
- Root SSH login enabled with password
- World-writable files in web root

**Priority 2 (WARN items — fix this week):**
- SSH password auth still enabled
- Apache leaking version info (ServerTokens/ServerSignature)
- PHP session cookies not secure
- No sysctl hardening
- Missing security headers on vhosts

**Priority 3 (INFO items — improve over time):**
- Install AIDE for file integrity
- Install logwatch for log summaries
- Add IP restrictions to phpMyAdmin
- Disable unused PHP functions

---

*Last updated: 2026-02-20*
*See also: `scripts/server-audit.sh` for automated checking*
