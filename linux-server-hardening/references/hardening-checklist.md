# Hardening Checklist — Full Commands

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

The end-to-end hardening reference for a fresh Ubuntu/Debian server
(22.04 or 24.04) running Nginx + PHP-FPM + MySQL/MariaDB + Redis. Every
section follows the same shape: back up the current config, apply the
change, test, and show the rollback. Paste-ready. Do one area at a time
on a live server, verify, then move to the next — never batch all of them
before a sanity check.

## Table of contents

- [Ground rules before you start](#ground-rules-before-you-start)
- [SSH hardening](#ssh-hardening)
- [UFW firewall](#ufw-firewall)
- [Kernel (sysctl)](#kernel-sysctl)
- [Nginx](#nginx)
- [PHP-FPM](#php-fpm)
- [MySQL / MariaDB](#mysql--mariadb)
- [Redis](#redis)
- [File permissions](#file-permissions)
- [Unattended-upgrades](#unattended-upgrades)
- [AppArmor](#apparmor)
- [PAM password policy and lockout](#pam-password-policy-and-lockout)
- [Idle session timeout](#idle-session-timeout)
- [auditd — starter rules](#auditd--starter-rules)
- [GRUB bootloader](#grub-bootloader)
- [Post-hardening verification](#post-hardening-verification)
- [Sources](#sources)

## Ground rules before you start

1. **Keep your existing SSH session open** until every hardening step is
   verified from a second shell. If you lock yourself out, that open shell
   is how you will recover.
2. **Snapshot the VM** or at minimum `tar czf ~/pre-hardening-etc.tgz /etc`
   so you can roll back the entire config tree if something breaks.
3. **Make one change at a time and test.** Batching changes makes
   diagnosis a nightmare when something breaks.
4. **Back up every config before editing:**

```bash
sudo cp -a /etc/ssh/sshd_config /etc/ssh/sshd_config.$(date +%F).bak
sudo cp -a /etc/sysctl.conf    /etc/sysctl.conf.$(date +%F).bak
sudo cp -a /etc/nginx/nginx.conf /etc/nginx/nginx.conf.$(date +%F).bak
sudo cp -a /etc/php/*/fpm/php.ini /tmp/php.ini.$(date +%F).bak
```

5. **Test before you reload.** Every service below has a config check
   (`sshd -t`, `nginx -t`, `apache2ctl configtest`, `nft -c`). Use it.

## SSH hardening

Put drop-in hardening in a separate file so the distro-shipped
`sshd_config` stays untouched:

```bash
sudo install -o root -g root -m 600 /dev/null /etc/ssh/sshd_config.d/99-hardening.conf
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<'EOF'
# /etc/ssh/sshd_config.d/99-hardening.conf
# Managed by linux-server-hardening — edit this file, not sshd_config.

# Identity
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Attack surface reduction
Protocol 2
MaxAuthTries 3
MaxSessions 2
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

# Disable everything forwarding-related unless you specifically need it
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
AllowStreamLocalForwarding no
GatewayPorts no
PermitTunnel no

# Who is allowed in (one of these two lines, not both)
# AllowUsers deploy admin
AllowGroups ssh-users

# Pre-login banner
Banner /etc/ssh/sshd-banner
EOF
```

Create the banner:

```bash
sudo tee /etc/ssh/sshd-banner >/dev/null <<'EOF'
**************************************************************
  Authorized access only. All activity is monitored and logged.
  Disconnect immediately if you are not an authorized user.
**************************************************************
EOF
sudo chmod 644 /etc/ssh/sshd-banner
```

Create the `ssh-users` group and add your operators:

```bash
sudo groupadd -f ssh-users
sudo usermod -aG ssh-users $USER
```

Test, then reload — keep your existing session open:

```bash
sudo sshd -t && sudo systemctl reload ssh
```

In a **new** terminal, verify:

```bash
ssh -v $USER@<host>      # should succeed with key
sudo sshd -T | grep -E 'permitrootlogin|passwordauth|allowgroups'
```

**Rollback:**

```bash
sudo rm /etc/ssh/sshd_config.d/99-hardening.conf
sudo systemctl reload ssh
```

## UFW firewall

Back up the current ruleset so you can pin it if needed:

```bash
sudo cp -a /etc/ufw /root/ufw.$(date +%F).bak
```

Apply the baseline policy:

```bash
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 22/tcp   comment 'SSH — rate-limited'
sudo ufw allow 80/tcp   comment 'HTTP (certbot + redirect)'
sudo ufw allow 443/tcp  comment 'HTTPS'
sudo ufw --force enable
sudo ufw status verbose
```

If this host is behind a load balancer, `ufw allow from <lb-cidr> to any port 443`
instead of opening 443 to the world.

**Test:**

```bash
sudo ufw status verbose | grep -E 'Status|Default'
sudo ss -tlnp | grep -E ':22|:80|:443'
nmap -Pn <host>          # from a remote host — should show 22/80/443 only
```

**Rollback:**

```bash
sudo ufw --force reset
sudo rsync -a /root/ufw.$(date +%F).bak/ /etc/ufw/
sudo ufw --force enable
```

## Kernel (sysctl)

All kernel tuning lives in **one** file so you can diff and roll back
cleanly. See `references/sysctl-reference.md` for every tunable with
rationale — this section shows only the apply/test/rollback flow.

```bash
sudo tee /etc/sysctl.d/99-linux-skills.conf >/dev/null <<'EOF'
# /etc/sysctl.d/99-linux-skills.conf
# Managed by linux-server-hardening.

# Kernel protections
kernel.randomize_va_space = 2
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
kernel.sysrq = 0
kernel.unprivileged_bpf_disabled = 1

# Core-dump hygiene
fs.suid_dumpable = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2

# IPv4 hardening
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_rfc1337 = 1

# IPv6 hardening
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
EOF
sudo sysctl --system
```

**Test:**

```bash
sysctl kernel.randomize_va_space kernel.kptr_restrict \
       net.ipv4.tcp_syncookies net.ipv4.conf.all.rp_filter
```

**Rollback:**

```bash
sudo rm /etc/sysctl.d/99-linux-skills.conf
sudo sysctl --system
```

## Nginx

Harden `nginx.conf` once at the http level, then use an included snippet
in every vhost so security headers are guaranteed.

```bash
sudo cp -a /etc/nginx/nginx.conf /etc/nginx/nginx.conf.$(date +%F).bak
```

Edit `/etc/nginx/nginx.conf` to include inside the `http { ... }` block:

```nginx
    # --- hardening (linux-server-hardening) ---
    server_tokens off;
    client_max_body_size 16m;
    client_body_timeout 12;
    client_header_timeout 12;
    keepalive_timeout 15;
    send_timeout 10;
    types_hash_max_size 2048;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 1.1.1.1 8.8.8.8 valid=300s;
    resolver_timeout 5s;

    include /etc/nginx/snippets/security-headers.conf;
    # ----------------------------------------
```

Create the security headers snippet:

```bash
sudo tee /etc/nginx/snippets/security-headers.conf >/dev/null <<'EOF'
# /etc/nginx/snippets/security-headers.conf
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
# Tighten CSP per app — starter:
add_header Content-Security-Policy "default-src 'self'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline'; script-src 'self'" always;
EOF
```

Create a dotfile/hidden file deny snippet and include it in every vhost:

```bash
sudo tee /etc/nginx/snippets/security-dotfiles.conf >/dev/null <<'EOF'
# /etc/nginx/snippets/security-dotfiles.conf
location ~ /\.(?!well-known).* {
    deny all;
    access_log off;
    log_not_found off;
}
location ~* \.(bak|backup|old|orig|save|swp|sql|sqlite|env)$ {
    deny all;
}
EOF
```

Test and reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
curl -sI https://localhost -k | grep -iE 'strict-transport|x-frame|x-content|server'
```

**Rollback:** restore the `.bak` file and reload.

## PHP-FPM

Back up, edit, test, reload:

```bash
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
sudo cp -a /etc/php/$PHP_VER/fpm/php.ini /etc/php/$PHP_VER/fpm/php.ini.$(date +%F).bak
```

Apply the hardening settings (`sed -i` in place, each idempotent):

```bash
sudo tee /etc/php/$PHP_VER/fpm/conf.d/99-hardening.ini >/dev/null <<'EOF'
; Managed by linux-server-hardening
expose_php = Off
display_errors = Off
display_startup_errors = Off
log_errors = On
error_log = /var/log/php/php_errors.log
allow_url_include = Off
allow_url_fopen = Off
file_uploads = On
upload_max_filesize = 16M
post_max_size = 20M
max_execution_time = 30
max_input_time = 30
memory_limit = 256M

; Session hardening
session.cookie_secure = 1
session.cookie_httponly = 1
session.use_strict_mode = 1
session.cookie_samesite = "Lax"
session.gc_maxlifetime = 1440

; Lock the dangerous toys
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,curl_multi_exec,parse_ini_file,show_source,pcntl_exec,eval
open_basedir = /var/www:/tmp:/var/lib/php
EOF
```

Create log directory:

```bash
sudo install -d -o www-data -g www-data -m 750 /var/log/php
sudo touch /var/log/php/php_errors.log
sudo chown www-data:www-data /var/log/php/php_errors.log
sudo chmod 640 /var/log/php/php_errors.log
```

Restart and verify:

```bash
sudo systemctl restart php$PHP_VER-fpm
php -i | grep -E 'expose_php|display_errors|allow_url_include|disable_functions' | head
```

**Rollback:** `sudo rm /etc/php/$PHP_VER/fpm/conf.d/99-hardening.ini && sudo systemctl restart php$PHP_VER-fpm`.

## MySQL / MariaDB

Bind to loopback and lock the installation:

```bash
sudo cp -a /etc/mysql /root/mysql-conf.$(date +%F).bak

# Set bind-address = 127.0.0.1 in the main server config
for f in /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mariadb.conf.d/50-server.cnf; do
    [ -f "$f" ] && sudo sed -i 's/^bind-address.*/bind-address = 127.0.0.1/' "$f"
done
sudo systemctl restart mysql || sudo systemctl restart mariadb
sudo ss -tlnp | grep 3306      # must show 127.0.0.1:3306
```

Run `mysql_secure_installation` and answer yes to every prompt:

```bash
sudo mysql_secure_installation
```

Manually verify the outcome:

```bash
sudo mysql <<'SQL'
SELECT user, host FROM mysql.user WHERE authentication_string = '' OR user = '';
SELECT user, host FROM mysql.user WHERE user = 'root';
SHOW DATABASES;
SQL
```

Expected: no empty-password rows, `root` only from `localhost`, no `test`
database.

**Rollback:** the bind-address change is reversible by editing the same
line back to `0.0.0.0`; `mysql_secure_installation` is not, but there is
no reason to undo it.

## Redis

```bash
sudo cp -a /etc/redis/redis.conf /etc/redis/redis.conf.$(date +%F).bak

sudo sed -i \
    -e 's/^bind .*/bind 127.0.0.1 -::1/' \
    -e 's/^# requirepass .*/requirepass '"$(openssl rand -base64 32)"'/' \
    -e 's/^protected-mode .*/protected-mode yes/' \
    /etc/redis/redis.conf

# Append renames only if they're not already there
grep -q '^rename-command FLUSHDB' /etc/redis/redis.conf || \
    sudo tee -a /etc/redis/redis.conf >/dev/null <<'EOF'

# --- linux-server-hardening ---
rename-command FLUSHDB  ""
rename-command FLUSHALL ""
rename-command CONFIG   ""
rename-command DEBUG    ""
rename-command SHUTDOWN ""
rename-command KEYS     ""
EOF

sudo systemctl restart redis
sudo ss -tlnp | grep 6379
```

Grab the generated password for your app config:

```bash
sudo grep '^requirepass' /etc/redis/redis.conf
```

**Test:**

```bash
redis-cli ping            # should fail with NOAUTH
redis-cli -a '<password>' ping   # should return PONG
```

**Rollback:** restore `redis.conf.bak` and restart.

## File permissions

```bash
# System critical files
sudo chown root:root /etc/passwd /etc/group
sudo chown root:shadow /etc/shadow /etc/gshadow
sudo chmod 644 /etc/passwd /etc/group
sudo chmod 640 /etc/shadow /etc/gshadow
sudo chmod 440 /etc/sudoers
sudo chmod 600 /etc/ssh/sshd_config

# Web root
sudo chown -R www-data:www-data /var/www/html
sudo find /var/www -type d -exec chmod 755 {} \;
sudo find /var/www -type f -exec chmod 644 {} \;
sudo find /var/www -type f -perm -0002 -exec chmod o-w {} \;

# Operator dotfiles (run as each operator, not with sudo)
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys 2>/dev/null
chmod 600 ~/.ssh/id_* 2>/dev/null
chmod 600 ~/.mysql-backup.cnf 2>/dev/null
chmod 600 ~/.backup-encryption-key 2>/dev/null
chmod 600 ~/.config/rclone/rclone.conf 2>/dev/null
chmod 600 ~/.pgpass 2>/dev/null
```

Verify:

```bash
stat -c '%a %U:%G %n' \
    /etc/shadow /etc/passwd /etc/sudoers /etc/ssh/sshd_config \
    ~/.ssh/authorized_keys ~/.config/rclone/rclone.conf 2>/dev/null
```

## Unattended-upgrades

```bash
sudo apt update
sudo apt install -y unattended-upgrades apt-listchanges
sudo dpkg-reconfigure -f noninteractive unattended-upgrades
```

Pin it to security + updates, set automatic reboot window:

```bash
sudo tee /etc/apt/apt.conf.d/52unattended-upgrades-local >/dev/null <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
    "${distro_id}:${distro_codename}-updates";
};
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:30";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
```

Verify with a dry run:

```bash
sudo unattended-upgrade --dry-run -d 2>&1 | tail -20
cat /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null | tail -20
```

## AppArmor

```bash
sudo apt install -y apparmor apparmor-profiles apparmor-profiles-extra apparmor-utils
sudo systemctl enable --now apparmor
sudo aa-status
```

Put web-facing profiles in enforce mode:

```bash
# Only enforce a profile after verifying it does not break the app.
sudo aa-enforce /etc/apparmor.d/usr.sbin.nginx 2>/dev/null
sudo aa-enforce /etc/apparmor.d/usr.sbin.mysqld 2>/dev/null
sudo aa-enforce /etc/apparmor.d/usr.bin.redis-server 2>/dev/null
```

Audit denials after the fact:

```bash
sudo grep -i denied /var/log/audit/audit.log /var/log/kern.log 2>/dev/null | tail
sudo aa-logprof          # interactively promote rules from complain to enforce
```

**Rollback** a profile that breaks the app:

```bash
sudo aa-complain /etc/apparmor.d/usr.sbin.nginx
```

## PAM password policy and lockout

Install pwquality and configure:

```bash
sudo apt install -y libpam-pwquality
sudo cp -a /etc/security/pwquality.conf /etc/security/pwquality.conf.$(date +%F).bak
sudo tee -a /etc/security/pwquality.conf >/dev/null <<'EOF'

# --- linux-server-hardening ---
minlen   = 14
minclass = 3
maxrepeat = 3
dcredit  = -1
ucredit  = -1
lcredit  = -1
ocredit  = -1
retry    = 3
EOF
grep pwquality /etc/pam.d/common-password
```

Lockout after 5 failed logins (Ubuntu 22.04+ ships `pam_faillock`):

```bash
sudo cp -a /etc/security/faillock.conf /etc/security/faillock.conf.$(date +%F).bak
sudo tee -a /etc/security/faillock.conf >/dev/null <<'EOF'

# --- linux-server-hardening ---
deny = 5
unlock_time = 600
fail_interval = 900
even_deny_root
EOF
sudo pam-auth-update --enable faillock
grep faillock /etc/pam.d/common-auth
```

Unlock a locked account:

```bash
sudo faillock --user <username> --reset
```

## Idle session timeout

```bash
sudo tee /etc/profile.d/autologout.sh >/dev/null <<'EOF'
TMOUT=600
readonly TMOUT
export TMOUT
EOF
sudo chmod +x /etc/profile.d/autologout.sh
```

New shells will auto-logout after 10 minutes idle. Existing shells unaffected.

## auditd — starter rules

```bash
sudo apt install -y auditd audispd-plugins
sudo systemctl enable --now auditd
sudo tee /etc/audit/rules.d/99-linux-skills.rules >/dev/null <<'EOF'
## linux-server-hardening starter ruleset — extend with aide-and-auditd.md
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group  -p wa -k identity
-w /etc/sudoers      -p wa -k priv-esc
-w /etc/sudoers.d/   -p wa -k priv-esc
-w /etc/ssh/sshd_config -p wa -k sshd
-w /var/log/auth.log -p wa -k auth-log
-w /etc/cron.d/   -p wa -k cron
-w /var/spool/cron/ -p wa -k cron
-a always,exit -F arch=b64 -F euid=0 -S execve -k root-exec
EOF
sudo augenrules --load
sudo systemctl restart auditd
sudo auditctl -l | head
```

Read audit events:

```bash
sudo ausearch -i -k identity | less
sudo aureport -i -k
sudo aureport --auth
```

## GRUB bootloader

```bash
sudo chmod 600 /boot/grub/grub.cfg
ls -l /boot/grub/grub.cfg          # should be -rw------- root root
```

Set a GRUB password for physical security:

```bash
sudo grub-mkpasswd-pbkdf2          # copy the resulting hash
sudo tee -a /etc/grub.d/40_custom >/dev/null <<'EOF'
set superusers="root"
password_pbkdf2 root grub.pbkdf2.sha512.10000.<PASTE_HASH_HERE>
EOF
sudo update-grub
```

## Post-hardening verification

After every step is complete, re-run the audit:

```bash
# Re-run linux-security-analysis
less ~/.claude/skills/linux-security-analysis/references/audit-layers.md

# Or if sk-audit is installed:
sudo sk-audit
```

Everything that was CRITICAL or HIGH before should now be PASS. Any
remaining findings are either deliberate exceptions or the next item on
your todo list.

## Optional fast path

Running `sudo install-skills-bin linux-server-hardening` installs
`sk-harden-ssh`, `sk-harden-sysctl`, and `sk-harden-php` which wrap the
commands in this document. They are convenience wrappers — the manual
steps above remain the source of truth.

## Sources

- *Mastering Linux Security and Hardening*, Donald A. Tevault, 3rd Edition,
  Packt — Chapter 2 (user accounts and sudo), Chapter 6 (SSH hardening),
  Chapter 8 (DAC), Chapter 11 (kernel hardening with sysctl), Chapter 12
  (scanning, auditing and hardening).
- *Practical Linux Security Cookbook*, Tajinder Kalsi, Packt — recipes for
  PAM, `faillock`, file permission hardening, and auditd.
- *Ubuntu Server Guide*, Canonical — "Security" chapter: UFW, OpenSSH,
  AppArmor, console security, users and groups, unattended-upgrades,
  certificates, and encrypted storage.
- CIS Ubuntu 22.04 LTS Benchmark (Level 1 Server) — numeric thresholds and
  lockout values.
- Manual pages: `sshd_config(5)`, `ufw(8)`, `sysctl(8)`, `nginx(8)`,
  `php-fpm.conf(5)`, `pam_pwquality(8)`, `pam_faillock(8)`, `auditctl(8)`.
