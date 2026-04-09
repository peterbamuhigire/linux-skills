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

## Branch 11: Open Port / Unexpected Listener

```bash
# See all listening TCP/UDP sockets with process names (replaces netstat)
sudo ss -tulpn
# or legacy:
sudo netstat -tulpn

# Check which process owns a specific port:
sudo ss -tulpn | grep :8080
sudo lsof -i :8080           # install: sudo apt install lsof

# All files open by a specific process (useful for zombie/stuck processes):
sudo lsof -p <pid>

# All network connections for a process name:
sudo lsof -i -n -P | grep nginx
```

Fix: `sudo ufw deny <port>/tcp` to block unexpected listeners | kill the process

## Branch 12: Tracing a Crashing or Misbehaving Process

```bash
# Trace system calls made by a command (shows what it opens, reads, writes):
strace -c -f <command>                  # summary table of syscalls
strace -e trace=file <command>          # only file-related syscalls
strace -p <pid>                         # attach to running process

# Confirm binary syscalls (security audit of what ls actually does):
strace -c -f -S name ls 2>&1 1>/dev/null | tail -n +3 | head -n -2 | awk '{print $(NF)}'
```

Install: `sudo apt install strace`

## Branch 13: Security Audit — Who Is Listening / What Accessed a File

```bash
# Install auditd (Ubuntu):
sudo apt install auditd

# List active audit rules:
sudo auditctl -l

# Watch /etc/passwd for writes/attribute changes:
sudo auditctl -w /etc/passwd -p wa -k passwd_changes

# Watch a directory for all access:
sudo auditctl -w /var/www/html/ -p rwxa -k webroot_watch

# Make rules permanent (survives reboot):
sudo sh -c "auditctl -l > /etc/audit/rules.d/custom.rules"
sudo systemctl restart auditd

# Search audit log by key:
sudo ausearch -i -k passwd_changes
sudo aureport -i -k | grep 'passwd_changes'

# Authentication report (who logged in, success/fail):
sudo aureport -au

# Look up a specific event number:
sudo ausearch -a <event_number>
```
