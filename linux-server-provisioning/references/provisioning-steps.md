# Server Provisioning — Full Commands

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Complete, ordered command reference for provisioning a fresh Ubuntu 22.04 / 24.04 (or Debian 12) server destined for production web hosting. Every section lists the exact commands to run, the expected output, and the verification step that must pass before moving on. The target end-state is a hardened server running the Nginx + Apache + PHP-FPM + MySQL + PostgreSQL + Redis stack with fail2ban, certbot auto-renewal, unattended security updates, rclone for backups, and the linux-skills repository cloned into `~/.claude/skills`. Nothing here depends on the `sk-*` scripts — those are optional wrappers; the commands below are the canonical procedure and always work.

## Table of contents

1. System update, hostname, timezone
2. Admin user with sudo
3. SSH hardening (drop-in)
4. UFW baseline (22/80/443)
5. Unattended security upgrades
6. Web stack (Nginx, Apache on 8080, PHP-FPM)
7. Databases (MySQL 8, PostgreSQL, Redis)
8. Supporting tools (fail2ban, certbot, rclone, msmtp, Node.js)
9. Nginx snippets library
10. Clone linux-skills into ~/.claude/skills
11. Post-install verification
12. Sources

---

## 1. System update, hostname, timezone

Run as root or via `sudo` from your first SSH session.

```bash
# Refresh package index and upgrade everything
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y

# Install the minimum tooling needed by later steps
sudo apt install -y \
    ca-certificates curl gnupg lsb-release \
    vim less htop tmux rsync net-tools dnsutils \
    ufw fail2ban unattended-upgrades apt-listchanges \
    software-properties-common

# Set the hostname (pick a short, DNS-valid name)
sudo hostnamectl set-hostname <server-name>
echo "127.0.1.1 <server-name>" | sudo tee -a /etc/hosts

# Set timezone
sudo timedatectl set-timezone Africa/Nairobi

# Generate and set locale
sudo locale-gen en_GB.UTF-8
sudo update-locale LANG=en_GB.UTF-8 LC_ALL=en_GB.UTF-8
```

**Verify:**

```bash
hostnamectl
# Expected: Static hostname: <server-name>, Operating System: Ubuntu 22.04.x or 24.04.x

timedatectl
# Expected: Time zone: Africa/Nairobi (EAT, +0300) ; NTP service: active

locale
# Expected: LANG=en_GB.UTF-8
```

**If the clock is skewed:**

```bash
sudo timedatectl set-ntp true
sudo systemctl status systemd-timesyncd
```

---

## 2. Admin user with sudo

Never run production services as root and never SSH in as root after this section.

```bash
sudo adduser administrator
# Set a strong password and fill in the GECOS fields (or press Enter)

sudo usermod -aG sudo administrator

# Copy the existing root SSH key to the new user (only if provisioning as root)
sudo mkdir -p /home/administrator/.ssh
sudo cp /root/.ssh/authorized_keys /home/administrator/.ssh/authorized_keys
sudo chown -R administrator:administrator /home/administrator/.ssh
sudo chmod 700 /home/administrator/.ssh
sudo chmod 600 /home/administrator/.ssh/authorized_keys

# Give the new user a sensible shell and dotfiles
sudo -u administrator tee /home/administrator/.bash_aliases >/dev/null <<'EOF'
alias ll='ls -laFh'
alias la='ls -A'
alias ..='cd ..'
alias ...='cd ../..'
alias gs='git status'
alias gd='git diff'
alias journal='sudo journalctl -f'
EOF
```

**Verify — in a NEW terminal, do not close the root session yet:**

```bash
ssh administrator@<server-ip>
id
# Expected: uid=1000(administrator) gid=1000(administrator) groups=1000(administrator),27(sudo)

sudo -v
# Expected: prompts for password, then returns cleanly
```

Only after the new session works should you close the root session.

---

## 3. SSH hardening (drop-in)

Debian/Ubuntu's sshd reads `/etc/ssh/sshd_config.d/*.conf`. Drop a single hardening file there — leave the main `sshd_config` untouched so package upgrades don't conflict.

```bash
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<'EOF'
# --- Access control ---
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes

# --- Hardening ---
Protocol 2
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitUserEnvironment no
MaxAuthTries 3
MaxSessions 4
LoginGraceTime 30s
ClientAliveInterval 300
ClientAliveCountMax 2

# --- Banner and logging ---
LogLevel VERBOSE

# --- Limit who can log in ---
AllowUsers administrator
EOF

# Test the new config without applying it
sudo sshd -t
# Expected: no output (silent success)
```

**Before reloading sshd**, keep the current SSH session open and open a second session in a new terminal.

```bash
# In the original session — test the config and reload
sudo sshd -t && sudo systemctl reload ssh

# In a NEW terminal — verify you can still log in
ssh administrator@<server-ip>
```

If the new session fails, the old session is still open — revert the file and retry:

```bash
sudo rm /etc/ssh/sshd_config.d/99-hardening.conf
sudo systemctl reload ssh
```

**Verify (once the new session works):**

```bash
sudo sshd -T | grep -Ei 'permitrootlogin|passwordauth|pubkeyauth|allowusers'
# Expected:
#   permitrootlogin no
#   passwordauthentication no
#   pubkeyauthentication yes
#   allowusers administrator
```

---

## 4. UFW baseline (22/80/443)

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow 22/tcp  comment 'SSH'
sudo ufw allow 80/tcp  comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'

sudo ufw --force enable
```

**Verify:**

```bash
sudo ufw status verbose
# Expected:
#   Status: active
#   Default: deny (incoming), allow (outgoing), deny (routed)
#   22/tcp    ALLOW IN  Anywhere
#   80/tcp    ALLOW IN  Anywhere
#   443/tcp   ALLOW IN  Anywhere
#   (same rules for v6)
```

Port 8080 (Apache backend) must **not** appear — it's bound to 127.0.0.1 and UFW denies external access anyway.

---

## 5. Unattended security upgrades

```bash
sudo apt install -y unattended-upgrades apt-listchanges

# Reconfigure at low priority so non-interactive defaults apply
sudo dpkg-reconfigure -plow unattended-upgrades

sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
```

Key edits:

```
// Enable security-only (keep updates + proposed OFF)
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

// Remove unused dependencies
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Reboot automatically at 04:00 if a kernel update requires it
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";

// Email the admin on failure
Unattended-Upgrade::Mail "root";
Unattended-Upgrade::MailReport "on-change";
```

Enable the timers:

```bash
sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Download-Upgradeable-Packages "1";
EOF
```

**Verify:**

```bash
sudo unattended-upgrade --dry-run --debug 2>&1 | tail -30
# Expected: "Initial blacklist: ... Packages that will be upgraded: ..."
#   with no "ERROR" lines.

sudo systemctl status apt-daily.timer apt-daily-upgrade.timer
# Expected: both active (waiting)
```

---

## 6. Web stack (Nginx, Apache on 8080, PHP-FPM)

### 6.1 Nginx

```bash
sudo apt install -y nginx
sudo systemctl enable --now nginx
```

### 6.2 Apache — move to 127.0.0.1:8080

```bash
sudo apt install -y apache2

# Change the listen address
sudo sed -i 's/^Listen .*/Listen 127.0.0.1:8080/' /etc/apache2/ports.conf

# Update the default site so it binds to the same address
sudo sed -i 's|<VirtualHost \*:80>|<VirtualHost 127.0.0.1:8080>|' \
    /etc/apache2/sites-available/000-default.conf

# Enable required modules
sudo a2enmod rewrite proxy proxy_fcgi setenvif remoteip headers

# Ensure MPM event (not prefork)
sudo a2dismod mpm_prefork 2>/dev/null || true
sudo a2enmod  mpm_event

sudo apache2ctl configtest
sudo systemctl enable --now apache2
sudo systemctl restart apache2
```

**Verify Apache is on loopback only:**

```bash
sudo ss -tlnp | grep apache2
# Expected: LISTEN 0 511 127.0.0.1:8080 0.0.0.0:* users:(("apache2",...))
# MUST NOT show 0.0.0.0:8080 or [::]:8080
```

### 6.3 PHP-FPM (PHP 8.3)

On Ubuntu 24.04, PHP 8.3 is in the default repo. On Ubuntu 22.04, add Ondřej Surý's PPA:

```bash
# Ubuntu 22.04 only:
sudo add-apt-repository -y ppa:ondrej/php
sudo apt update

sudo apt install -y \
    php8.3-fpm php8.3-cli php8.3-common \
    php8.3-mysql php8.3-pgsql \
    php8.3-curl php8.3-mbstring php8.3-xml \
    php8.3-zip php8.3-gd php8.3-intl \
    php8.3-bcmath php8.3-redis php8.3-opcache

sudo systemctl enable --now php8.3-fpm
```

If you need a second PHP version (for legacy apps), repeat with `php8.2-*` or `php7.4-*` and you'll get a parallel pool at `/run/php/php8.2-fpm.sock`.

**Verify:**

```bash
php -v
# Expected: PHP 8.3.x (cli)

sudo systemctl is-active nginx apache2 php8.3-fpm
# Expected: active active active

ls /run/php/
# Expected: php8.3-fpm.sock  php8.3-fpm.pid
```

---

## 7. Databases (MySQL 8, PostgreSQL, Redis)

### 7.1 MySQL 8

```bash
sudo apt install -y mysql-server
sudo systemctl enable --now mysql

# Interactive security wizard — set root password and answer Y to everything
sudo mysql_secure_installation

# Bind to loopback only
sudo sed -i 's/^bind-address.*/bind-address = 127.0.0.1/' /etc/mysql/mysql.conf.d/mysqld.cnf
# If the line is missing, add under [mysqld]
grep -q '^bind-address' /etc/mysql/mysql.conf.d/mysqld.cnf || \
    echo "bind-address = 127.0.0.1" | sudo tee -a /etc/mysql/mysql.conf.d/mysqld.cnf

sudo systemctl restart mysql
```

**Verify:**

```bash
sudo ss -tlnp | grep 3306
# Expected: LISTEN 0 ... 127.0.0.1:3306 ... users:(("mysqld",...))

sudo mysql -e 'SELECT VERSION();'
# Expected: 8.0.x or 8.4.x
```

### 7.2 PostgreSQL

```bash
sudo apt install -y postgresql postgresql-contrib
sudo systemctl enable --now postgresql
```

PostgreSQL defaults to local-socket-only access in the Ubuntu packaging, so no bind-address tweak is needed.

**Verify:**

```bash
sudo -u postgres psql -c 'SELECT version();'
# Expected: PostgreSQL 14.x (22.04) or 16.x (24.04)
```

### 7.3 Redis

```bash
sudo apt install -y redis-server

# Ensure loopback bind and set a password
sudo sed -i 's/^# requirepass .*/requirepass <strong-redis-password>/' /etc/redis/redis.conf
# If the commented line doesn't exist, append:
grep -q '^requirepass ' /etc/redis/redis.conf || \
    echo "requirepass <strong-redis-password>" | sudo tee -a /etc/redis/redis.conf

# bind 127.0.0.1 -::1 is already the Debian default — confirm it
grep '^bind ' /etc/redis/redis.conf

# supervised systemd
sudo sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf

sudo systemctl enable --now redis-server
sudo systemctl restart redis-server
```

**Verify:**

```bash
sudo ss -tlnp | grep 6379
# Expected: 127.0.0.1:6379 only

redis-cli -a '<strong-redis-password>' PING
# Expected: PONG
```

---

## 8. Supporting tools

### 8.1 fail2ban

```bash
sudo apt install -y fail2ban

# Local jail override — the Debian package ships with /etc/fail2ban/jail.conf;
# we write our edits to jail.local which survives package upgrades.
sudo tee /etc/fail2ban/jail.local >/dev/null <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled = true

[nginx-http-auth]
enabled = true

[nginx-badbots]
enabled = true
EOF

sudo systemctl enable --now fail2ban
sudo fail2ban-client status
# Expected: Number of jail: 3 ; Jail list: sshd, nginx-http-auth, nginx-badbots
```

### 8.2 certbot (nginx plugin)

```bash
sudo apt install -y certbot python3-certbot-nginx python3-certbot-apache

# The certbot package installs systemd timers automatically:
sudo systemctl status certbot.timer
# Expected: active (waiting)

# Dry-run — no certs exist yet, so this should print a trivial success
sudo certbot renew --dry-run
# Expected: "No renewals were attempted." (zero certs, no failures)
```

### 8.3 rclone

```bash
curl https://rclone.org/install.sh | sudo bash
rclone version
# Expected: rclone v1.6x.x

# Configure remotes interactively (e.g. B2, S3, Drive, SFTP)
sudo -u administrator rclone config
```

### 8.4 msmtp (outbound mail via external SMTP)

```bash
sudo apt install -y msmtp msmtp-mta mailutils

sudo tee /etc/msmtprc >/dev/null <<'EOF'
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           smtp.example.com
port           587
from           alerts@<domain>
user           alerts@<domain>
password       <smtp-password>
EOF

sudo chmod 600 /etc/msmtprc
sudo chown root:root /etc/msmtprc

# Send a test mail
echo "Provisioning complete on $(hostname)" | mail -s "Server up" you@example.com
```

### 8.5 Node.js LTS

```bash
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs
node --version   # Expected: v20.x or later
npm --version    # Expected: 10.x or later
```

---

## 9. Nginx snippets library

```bash
sudo mkdir -p /etc/nginx/snippets

# --- security-dotfiles.conf ---
sudo tee /etc/nginx/snippets/security-dotfiles.conf >/dev/null <<'EOF'
location ~ /\.(?!well-known) { deny all; return 404; }
location ~* \.(env|git|sql|bak|backup|old|orig|swp|htpasswd|htaccess|ini|yaml|yml|lock|dist)$ { deny all; return 404; }
EOF

# --- security-headers.conf ---
sudo tee /etc/nginx/snippets/security-headers.conf >/dev/null <<'EOF'
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Content-Type-Options    "nosniff" always;
add_header X-Frame-Options           "SAMEORIGIN" always;
add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
add_header Permissions-Policy        "camera=(), microphone=(), geolocation=(), interest-cohort=()" always;
add_header X-XSS-Protection          "0" always;
EOF

# --- ssl-params.conf ---
sudo tee /etc/nginx/snippets/ssl-params.conf >/dev/null <<'EOF'
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;
resolver 1.1.1.1 8.8.8.8 valid=300s;
resolver_timeout 5s;
EOF

# --- acme-challenge.conf ---
sudo tee /etc/nginx/snippets/acme-challenge.conf >/dev/null <<'EOF'
location ^~ /.well-known/acme-challenge/ {
    default_type "text/plain";
    root /var/www/html;
    allow all;
}
EOF

# --- proxy-to-apache.conf ---
sudo tee /etc/nginx/snippets/proxy-to-apache.conf >/dev/null <<'EOF'
proxy_pass http://127.0.0.1:8080;
proxy_http_version 1.1;
proxy_set_header Host              $host;
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host  $host;
proxy_set_header X-Forwarded-Port  $server_port;
proxy_connect_timeout 15s;
proxy_send_timeout    60s;
proxy_read_timeout    60s;
EOF

# --- fastcgi-php.conf ---
sudo tee /etc/nginx/snippets/fastcgi-php.conf >/dev/null <<'EOF'
fastcgi_pass unix:/run/php/php8.3-fpm.sock;
fastcgi_index index.php;
fastcgi_split_path_info ^(.+\.php)(/.+)$;
fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
fastcgi_param PATH_INFO $fastcgi_path_info;
fastcgi_param HTTPS $https if_not_empty;
include fastcgi_params;
fastcgi_read_timeout 60s;
fastcgi_intercept_errors on;
EOF

# --- static-files.conf ---
sudo tee /etc/nginx/snippets/static-files.conf >/dev/null <<'EOF'
location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp|avif|woff|woff2|ttf|eot|otf)$ {
    expires 1y;
    add_header Cache-Control "public, immutable" always;
    access_log off;
    try_files $uri =404;
}
EOF

# --- catch-all vhost (reject unknown hostnames) ---
sudo tee /etc/nginx/sites-available/00-default.conf >/dev/null <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    ssl_certificate     /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;
    server_name _;
    return 444;
}
EOF
sudo apt install -y ssl-cert
sudo make-ssl-cert generate-default-snakeoil --force-overwrite
sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/00-default.conf /etc/nginx/sites-enabled/

# Hide nginx version
sudo sed -i 's/# server_tokens off;/server_tokens off;/' /etc/nginx/nginx.conf

sudo nginx -t && sudo systemctl reload nginx
```

**Verify:**

```bash
curl -sI -H "Host: bogus.example" http://127.0.0.1/ --max-time 3 || echo "(connection closed — catch-all works)"
curl -sI http://127.0.0.1/ | grep -i '^server:'
# Expected: Server: nginx   (no version)
```

---

## 10. Clone linux-skills into ~/.claude/skills

linux-skills IS the Claude Code skills directory. Cloning it to `~/.claude/skills` makes every skill load automatically whenever Claude Code starts on this server.

```bash
sudo -u administrator bash <<'EOF'
mkdir -p ~/.claude
cd ~/.claude
if [ -d skills/.git ]; then
    cd skills && git pull
else
    git clone <linux-skills-repo-url> skills
fi
EOF

# Wire up the two update helpers that every skill references
sudo cp /home/administrator/.claude/skills/scripts/update-all-repos /usr/local/bin/update-all-repos
sudo chmod +x /usr/local/bin/update-all-repos

sudo tee /usr/local/bin/update-repos >/dev/null <<'EOF'
#!/bin/bash
exec /usr/local/bin/update-all-repos "$@"
EOF
sudo chmod +x /usr/local/bin/update-repos

# Symlink server-audit.sh as /usr/local/bin/check-server-security
sudo ln -sf /home/administrator/.claude/skills/scripts/server-audit.sh \
    /usr/local/bin/check-server-security
sudo chmod +x /usr/local/bin/check-server-security

# (Optional) run the setup helper that the repo ships
sudo -u administrator bash /home/administrator/.claude/skills/scripts/setup-claude-code.sh
```

**Verify:**

```bash
ls /home/administrator/.claude/skills/
# Expected: CLAUDE.md, linux-webstack/, linux-site-deployment/, ...

which update-all-repos check-server-security
# Expected: /usr/local/bin/update-all-repos, /usr/local/bin/check-server-security
```

---

## 11. Post-install verification

Final sweep. Everything below must pass before putting the server into production.

### 11.1 Full service state

```bash
for s in ssh nginx apache2 php8.3-fpm mysql postgresql redis-server fail2ban certbot.timer unattended-upgrades; do
    printf '%-25s %s\n' "$s" "$(systemctl is-active $s 2>/dev/null)"
done
# Expected: every line shows "active"
```

### 11.2 Firewall

```bash
sudo ufw status verbose
# Expected: 22, 80, 443 ALLOW ; 8080 NOT LISTED
```

### 11.3 Port bindings

```bash
sudo ss -tlnp | grep -E 'nginx|apache2|mysqld|postgres|redis|sshd'
# Expected:
#   sshd       0.0.0.0:22
#   nginx      0.0.0.0:80, 0.0.0.0:443
#   apache2    127.0.0.1:8080            (loopback only)
#   mysqld     127.0.0.1:3306            (loopback only)
#   postgres   127.0.0.1:5432            (loopback only)
#   redis      127.0.0.1:6379            (loopback only)
```

### 11.4 fail2ban jails

```bash
sudo fail2ban-client status
sudo fail2ban-client status sshd
# Expected: Currently failed: 0, Total failed: 0 (or small numbers), Banned IP list: (empty on a new box)
```

### 11.5 certbot auto-renewal

```bash
sudo systemctl status certbot.timer
sudo certbot renew --dry-run
# Expected: "No renewals were attempted" (0 certs) or "Congratulations, all renewals succeeded"
```

### 11.6 Run the bundled audit

```bash
sudo check-server-security
# Expected: every check PASS. Investigate any FAIL before going to production.
```

### 11.7 Write down what you just built

Update `/etc/motd` or `~/server-notes.md` with:
- Hostname, IP, timezone
- Admin user name
- PHP version, MySQL/Postgres/Redis versions
- Which backup target rclone uses
- Which SMTP provider msmtp uses
- Date of provisioning and who did it

---

## 12. Sources

- Atef, Ghada. *Mastering Ubuntu: A Comprehensive Guide to Linux's Favorite.* 2023 — Chapter III (Getting Started), Chapter V (Advanced System Administration), Chapter VI (Ubuntu for Servers) covering hostname, timezone, user management, SSH, UFW, web servers, and databases.
- Canonical. *Ubuntu Server Guide — Linux 20.04 LTS (Focal).* 2020 — entire reference, notably the chapters on security, networking, web servers, databases, and unattended upgrades.
- `man 5 sshd_config`, `man 8 ufw`, `man 5 apt.conf`, `man 8 unattended-upgrade`, `man 1 mysql_secure_installation`.
- Debian/Ubuntu packaging defaults in `/etc/apache2/`, `/etc/nginx/`, `/etc/php/8.3/`, `/etc/mysql/`, `/etc/postgresql/`, `/etc/redis/`.
