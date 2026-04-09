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

## SSH Access Control (AllowUsers / AllowGroups)

Restrict SSH access to specific users or groups. Add to `/etc/ssh/sshd_config.d/99-hardening.conf`:

```
# Only allow named users (takes precedence over AllowGroups)
AllowUsers alice bob
# OR: only allow members of this group
AllowGroups sshusers

# Disable SSH tunneling (prevents firewall bypass)
AllowTcpForwarding no
AllowStreamLocalForwarding no
GatewayPorts no
PermitTunnel no

# Login grace period and session limits
LoginGraceTime 30
MaxSessions 2

# Pre-login security banner
Banner /etc/ssh/sshd-banner
```

Create the banner file:
```bash
sudo bash -c 'echo "WARNING: Authorized users only. All access is logged." > /etc/ssh/sshd-banner'
sudo chmod 644 /etc/ssh/sshd-banner
sudo sshd -t && sudo systemctl restart sshd
```

## Idle Session Timeout (Local + SSH)

Auto-logout idle sessions for all users (console + SSH):
```bash
sudo bash -c 'cat > /etc/profile.d/autologout.sh <<EOF
TMOUT=300
readonly TMOUT
export TMOUT
EOF'
sudo chmod +x /etc/profile.d/autologout.sh
```

## Additional Kernel Hardening (sysctl)

Append to `/etc/sysctl.d/99-security.conf`:
```ini
# Prevent ptrace abuse (1 = parent processes only, 2 = root only, 3 = disable)
kernel.yama.ptrace_scope = 1

# Prevent core dumps from SUID programs
fs.suid_dumpable = 0

# Protect hard and symbolic links
fs.protected_hardlinks = 1
fs.protected_symlinks = 1

# Additional IPv6 redirect protection
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0

# Log martians on default interface too
net.ipv4.conf.default.log_martians = 1
```
```bash
sudo sysctl --system
```

## PAM Password Policy (Ubuntu — pwquality)

```bash
sudo apt install -y libpam-pwquality
sudo nano /etc/security/pwquality.conf
```
```ini
minlen = 14
minclass = 3
maxrepeat = 3
```

Verify it's active in PAM:
```bash
grep pwquality /etc/pam.d/common-password
# Should show: password requisite pam_pwquality.so retry=3
```

## PAM Account Lockout (Ubuntu — faillock)

Ubuntu 20.04+ uses `pam_faillock`. Edit `/etc/security/faillock.conf`:
```ini
deny = 5
unlock_time = 600
even_deny_root
```

Verify PAM is calling faillock:
```bash
grep faillock /etc/pam.d/common-auth
# Ubuntu 22.04+ includes pam_faillock automatically via pam-auth-update
sudo pam-auth-update   # enable "Faillock" module if not already checked
```

Manually unlock a locked account:
```bash
sudo faillock --user <username> --reset
```

## AppArmor (Ubuntu)

```bash
# Check status
sudo apparmor_status

# Install extra profiles
sudo apt install -y apparmor-profiles apparmor-utils

# See all profiles and their modes
sudo aa-status

# Put a profile in enforce mode
sudo aa-enforce /usr/sbin/nginx

# Put a profile in complain (audit) mode
sudo aa-complain /usr/sbin/nginx

# Reload a modified profile
sudo apparmor_parser -r /etc/apparmor.d/usr.sbin.nginx
```

## auditd — Key Security Rules

```bash
sudo apt install -y auditd audispd-plugins
sudo systemctl enable --now auditd
```

Create `/etc/audit/rules.d/99-hardening.rules`:
```bash
sudo tee /etc/audit/rules.d/99-hardening.rules <<'EOF'
# Monitor changes to passwd and shadow files
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/group  -p wa -k group_changes
-w /etc/sudoers -p wa -k sudoers_changes

# Monitor sudo command execution (syscall execve by root via sudo)
-a always,exit -F arch=b64 -F euid=0 -S execve -k sudo_exec

# Monitor SSH config changes
-w /etc/ssh/sshd_config -p wa -k sshd_config_changes

# Monitor cron jobs
-w /etc/crontab -p wa -k crontab_changes
-w /etc/cron.d/ -p wa -k cron_changes
-w /var/spool/cron/ -p wa -k user_cron_changes

# Monitor login/logout events
-w /var/log/auth.log -p wa -k auth_log
-w /var/run/faillock/ -p wa -k faillock
EOF

sudo augenrules --load
sudo systemctl restart auditd
```

Search and report audit events:
```bash
# Search by key
sudo ausearch -i -k passwd_changes | less

# Generate a report of all key events
sudo aureport -i -k

# Authentication report
sudo aureport --auth

# View current active rules
sudo auditctl -l
```

## GRUB Bootloader Permissions (Ubuntu)

```bash
# Restrict grub.cfg so only root can read it
sudo chmod 600 /boot/grub/grub.cfg

# Verify
ls -l /boot/grub/grub.cfg
# Should show: -rw------- root root ...
```

Generate a GRUB password hash to prevent kernel parameter edits:
```bash
grub-mkpasswd-pbkdf2
# Copy the resulting hash, then add to /etc/grub.d/40_custom:
# set superusers="root"
# password_pbkdf2 root grub.pbkdf2.sha512.10000.<hash>
sudo update-grub
```
