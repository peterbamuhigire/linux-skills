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

## Special Permissions (SUID, SGID, Sticky Bit)

```bash
# View special permission bits on a file
ls -la /usr/bin/passwd        # -rwsr-xr-x: the 's' means SUID

# Set SUID (run as file owner regardless of who executes)
chmod u+s /path/to/binary
chmod 4755 /path/to/binary    # numeric: 4=SUID, 2=SGID, 1=sticky

# Set SGID on a directory (new files inherit group)
chmod g+s /var/shared
chmod 2755 /var/shared

# Set sticky bit on shared directories (only owner can delete their files)
chmod +t /tmp
chmod 1777 /tmp               # world-writable + sticky

# Remove all special bits
chmod -s /path/to/binary      # remove SUID/SGID
chmod -t /tmp                  # remove sticky bit

# Find all SUID/SGID binaries system-wide
find / -perm /6000 -type f 2>/dev/null
```

## Default Permission Mask (umask)

```bash
# Check current umask (022 = new files 644, new dirs 755)
umask

# Set umask for session
umask 027     # more restrictive: files 640, dirs 750

# Make persistent in /etc/profile or ~/.bashrc:
# echo "umask 027" >> /etc/profile
```

## Immutable Files (chattr / lsattr)

```bash
# View file attributes
lsattr /etc/passwd /etc/shadow /etc/sudoers

# Set immutable flag (prevents modification even by root until flag removed)
sudo chattr +i /etc/resolv.conf

# Remove immutable flag
sudo chattr -i /etc/resolv.conf

# Append-only (useful for log files)
sudo chattr +a /var/log/auth.log
```

## User Account Hardening

```bash
# Create a new user with home dir and bash shell
sudo useradd -m -s /bin/bash username

# Create a system/service account (no login shell, no home dir)
sudo useradd --system --no-create-home --shell /usr/sbin/nologin serviceuser

# Lock an account (prepends ! to shadow hash)
sudo passwd -l username
sudo usermod -L username       # equivalent

# Unlock an account
sudo passwd -u username
sudo usermod -U username

# Expire an account immediately (forces re-auth or blocks login)
sudo usermod -e 1 username     # date in days since epoch; 1 = expired
sudo chage -E 0 username       # equivalent using chage

# Check account status (P=active, L=locked, NP=no password)
sudo passwd -S username

# Set password expiry policy for a user
sudo chage -M 90 -m 7 -W 14 username    # max 90 days, min 7 days, warn 14 days

# List password aging info
sudo chage -l username
```

## Login Activity Auditing

```bash
# Last logins for all users
lastlog

# Recent login/logout history
last -n 30

# Currently logged-in users with activity
w

# Failed login attempts
sudo faillog -a 2>/dev/null | grep -v "^Login\|^$\|  0  " | head -20

# Who is logged in (simple)
who
```

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
