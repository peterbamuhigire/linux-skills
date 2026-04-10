# Post-Install Verification Checklist

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Once `references/provisioning-steps.md` has been walked through end to end, this checklist is the final gate before the server is released into production. Every item is a single command to run, the expected result, and the remediation to apply if the result is wrong. Run the whole sheet top-to-bottom on a freshly provisioned Ubuntu 22.04 / 24.04 server; a clean pass means the server is safe to host public sites. A single failure is enough to keep it out of production until fixed.

## Table of contents

1. OS and kernel
2. Admin user and sudo
3. SSH — key-only login
4. UFW firewall
5. fail2ban
6. Unattended security upgrades
7. Service state (Nginx, Apache, PHP-FPM, MySQL, PostgreSQL, Redis, fail2ban)
8. certbot and auto-renewal
9. Hostname, FQDN, timezone, locale
10. Swap and memory
11. Backup target (rclone)
12. Outbound mail (msmtp)
13. `/var/www/` permissions
14. Sources

---

## 1. OS and kernel

**Check:**
```bash
lsb_release -ds
uname -rm
```
**Expected:**
- `Ubuntu 22.04.x LTS` or `Ubuntu 24.04.x LTS` (or `Debian GNU/Linux 12 (bookworm)`).
- Kernel `5.15.x` / `6.8.x` (22.04 / 24.04) on `x86_64` or `aarch64`.

**Remediation if wrong:**
- Running an unsupported release → reprovision on a supported LTS. Non-LTS releases lose security updates quickly.
- Outdated kernel because `unattended-upgrades` hasn't caught up yet: `sudo apt update && sudo apt upgrade -y && sudo reboot` during a maintenance window.

---

## 2. Admin user and sudo

**Check:**
```bash
id administrator
sudo -lU administrator
getent passwd administrator
```
**Expected:**
- `uid=1000(administrator) gid=1000(administrator) groups=1000(administrator),27(sudo)`
- sudo output: `User administrator may run the following commands: ALL`
- passwd entry ending in `/bin/bash` (or `/usr/bin/bash`).

**Remediation:**
- User missing: `sudo adduser administrator && sudo usermod -aG sudo administrator` (see provisioning Section 2).
- User missing sudo group: `sudo usermod -aG sudo administrator`.
- Wrong shell: `sudo chsh -s /bin/bash administrator`.

---

## 3. SSH — key-only login

**Check:**
```bash
sudo sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|allowusers|maxauthtries)'
```
**Expected:**
```
permitrootlogin no
pubkeyauthentication yes
passwordauthentication no
kbdinteractiveauthentication no
allowusers administrator
maxauthtries 3
```

**Check the authorized_keys file:**
```bash
sudo stat -c '%U:%G %a %n' /home/administrator/.ssh /home/administrator/.ssh/authorized_keys
sudo wc -l /home/administrator/.ssh/authorized_keys
```
**Expected:**
- `/home/administrator/.ssh` owned by `administrator:administrator`, mode `700`.
- `authorized_keys` owned by `administrator:administrator`, mode `600`, at least one line.

**Remediation:**
- Any wrong `sshd -T` value: edit `/etc/ssh/sshd_config.d/99-hardening.conf`, run `sudo sshd -t`, then `sudo systemctl reload ssh` — **keep the current session open and verify login in a new terminal first**.
- Wrong perms: `sudo chown -R administrator:administrator /home/administrator/.ssh && sudo chmod 700 /home/administrator/.ssh && sudo chmod 600 /home/administrator/.ssh/authorized_keys`.

---

## 4. UFW firewall

**Check:**
```bash
sudo ufw status verbose
```
**Expected:**
```
Status: active
Default: deny (incoming), allow (outgoing), deny (routed)
22/tcp    ALLOW IN    Anywhere
80/tcp    ALLOW IN    Anywhere
443/tcp   ALLOW IN    Anywhere
22/tcp (v6)  ALLOW IN    Anywhere (v6)
80/tcp (v6)  ALLOW IN    Anywhere (v6)
443/tcp (v6) ALLOW IN    Anywhere (v6)
```
**Critical:** port 8080 (Apache backend) must **not** appear; any database port (3306/5432/6379) must **not** appear.

**Remediation:**
- UFW inactive: `sudo ufw enable` (warns about breaking existing SSH — the 22/tcp rule is already in the pending set).
- Extra ports open that shouldn't be: `sudo ufw delete allow <port>/tcp`.
- Missing 22/80/443: `sudo ufw allow 22/tcp comment SSH && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp`.

---

## 5. fail2ban

**Check:**
```bash
sudo systemctl is-active fail2ban
sudo fail2ban-client status
sudo fail2ban-client status sshd
```
**Expected:**
- `active`
- `Number of jail: 1` or more, with `sshd` in the jail list.
- `sshd` jail status shows the file list `/var/log/auth.log` or the systemd journal, and `Currently banned: 0` (or a small number on an already-live server).

**Remediation:**
- Not installed: `sudo apt install -y fail2ban && sudo systemctl enable --now fail2ban`.
- `sshd` jail missing: create `/etc/fail2ban/jail.local` (see provisioning Section 8.1) and `sudo systemctl restart fail2ban`.
- Jail enabled but not finding the log: on systemd-journal systems, set `backend = systemd` in the jail.

---

## 6. Unattended security upgrades

**Check:**
```bash
sudo systemctl status apt-daily.timer apt-daily-upgrade.timer
sudo unattended-upgrade --dry-run --debug 2>&1 | tail -20
```
**Expected:**
- Both timers `active (waiting)`.
- Dry-run output ends with a "Packages that will be upgraded" block (even if empty) and no `ERROR` lines.

**Remediation:**
- Timers inactive: `sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer`.
- Dry-run errors: usually a broken third-party repo — inspect `/etc/apt/sources.list.d/` and remove the offender.
- No upgrades happening: verify `/etc/apt/apt.conf.d/20auto-upgrades` exists and contains `APT::Periodic::Unattended-Upgrade "1";`.

---

## 7. Service state

**Check:**
```bash
for s in ssh nginx apache2 php8.3-fpm mysql postgresql redis-server fail2ban; do
    printf '%-20s %s\n' "$s" "$(systemctl is-active $s)"
done
```
**Expected:** every line shows `active`.

**Port bindings check:**
```bash
sudo ss -tlnp | grep -E 'nginx|apache2|mysqld|postgres|redis|sshd' | sort
```
**Expected:**
```
sshd       0.0.0.0:22       (public — SSH)
nginx      0.0.0.0:80
nginx      0.0.0.0:443
apache2    127.0.0.1:8080   (loopback only — critical)
mysqld     127.0.0.1:3306   (loopback only)
postgres   127.0.0.1:5432   (loopback only)
redis      127.0.0.1:6379   (loopback only)
```

**Remediation for a failing service:**
```bash
sudo systemctl status <service>
sudo journalctl -u <service> -n 100 --no-pager
```
Fix the root cause (usually a config typo) rather than restarting blindly.

**Remediation for Apache on `0.0.0.0:8080` instead of loopback:**
- `sudo sed -i 's/^Listen .*/Listen 127.0.0.1:8080/' /etc/apache2/ports.conf`
- `sudo sed -i 's|<VirtualHost \*:8080>|<VirtualHost 127.0.0.1:8080>|' /etc/apache2/sites-available/000-default.conf`
- `sudo systemctl restart apache2`

**Remediation for MySQL/Postgres/Redis on a non-loopback address:**
- MySQL: set `bind-address = 127.0.0.1` in `/etc/mysql/mysql.conf.d/mysqld.cnf`.
- Postgres: set `listen_addresses = 'localhost'` in `/etc/postgresql/*/main/postgresql.conf`.
- Redis: set `bind 127.0.0.1 -::1` in `/etc/redis/redis.conf`.
- Restart the affected service.

---

## 8. certbot and auto-renewal

**Check:**
```bash
which certbot
certbot --version
sudo systemctl status certbot.timer
sudo certbot renew --dry-run
```
**Expected:**
- `/usr/bin/certbot`, version `1.x` or newer.
- Timer `active (waiting)`.
- Dry-run output either `No renewals were attempted` (fresh box with zero certs) or `Congratulations, all renewals succeeded`.

**Remediation:**
- Not installed: `sudo apt install -y certbot python3-certbot-nginx python3-certbot-apache`.
- Timer missing: reinstall the package — the Debian/Ubuntu packaging ships the timer.
- Dry-run failure: read `/var/log/letsencrypt/letsencrypt.log` and fix the named vhost; the most common cause is a broken `include` in an Nginx vhost that stops `nginx -t`.

---

## 9. Hostname, FQDN, timezone, locale

**Check:**
```bash
hostnamectl
timedatectl
locale
hostname -f
```
**Expected:**
- `Static hostname: <server-name>`
- `Operating System: Ubuntu 22.04.x LTS` or newer
- `Time zone: Africa/Nairobi (EAT, +0300)` (or your configured zone)
- `System clock synchronized: yes`, `NTP service: active`
- `LANG=en_GB.UTF-8`, `LC_ALL=en_GB.UTF-8`
- `hostname -f` returns a fully qualified name (e.g. `srv1.example.com`) — **not** `localhost` or just the short hostname.

**Remediation:**
- Wrong hostname: `sudo hostnamectl set-hostname <server-name>` and update `/etc/hosts` to include `127.0.1.1 <server-name> <fqdn>`.
- FQDN returns `localhost`: add `127.0.1.1 <fqdn> <shortname>` to `/etc/hosts`.
- Clock not synced: `sudo timedatectl set-ntp true && sudo systemctl restart systemd-timesyncd`.
- Locale wrong: `sudo locale-gen en_GB.UTF-8 && sudo update-locale LANG=en_GB.UTF-8`.

---

## 10. Swap and memory

**Check:**
```bash
free -h
swapon --show
```
**Expected:**
- `free -h` shows `Mem:` with sensible totals (at least 1 GB for any production box).
- `swapon --show` shows either a swap partition/file, or — on cloud VMs that explicitly disable swap — no output. Either is acceptable, but **document which choice applies.**

**Remediation — add a 2 GB swap file if memory is tight:**
```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
sudo sysctl vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.d/99-swappiness.conf
```

Document the decision in `~/server-notes.md`:

```
Swap: 2 GB file at /swapfile, swappiness=10
# OR
Swap: disabled — Hetzner/DO recommendation for SSD-backed VMs
```

---

## 11. Backup target (rclone)

**Check:**
```bash
which rclone
rclone version
sudo -u administrator rclone listremotes
```
**Expected:**
- rclone installed, version `1.6x` or newer.
- At least one remote listed (e.g. `backup:`, `b2:`, `drive:`).

**Smoke-test:**
```bash
sudo -u administrator rclone lsd <remote-name>: --max-depth 1
```
**Expected:** a directory listing (even if empty — no error is a pass).

**Remediation:**
- Not installed: `curl https://rclone.org/install.sh | sudo bash`.
- No remotes: `sudo -u administrator rclone config` and add the backup target interactively.
- Auth error: re-run `rclone config reconnect <remote>:` for OAuth remotes.

---

## 12. Outbound mail (msmtp)

**Check:**
```bash
which msmtp mail
sudo stat -c '%U:%G %a %n' /etc/msmtprc
echo "post-install test from $(hostname) at $(date)" | mail -s "msmtp test" <your-email>
sudo tail /var/log/msmtp.log
```
**Expected:**
- `/usr/bin/msmtp` and `/usr/bin/mail` present.
- `/etc/msmtprc` owned by `root:root`, mode `600`.
- `msmtp.log` shows a recent line ending in `delivery status: 250`.
- Email arrives in your inbox.

**Remediation:**
- Not installed: `sudo apt install -y msmtp msmtp-mta mailutils`.
- `/etc/msmtprc` not at `0600 root:root`: `sudo chmod 600 /etc/msmtprc && sudo chown root:root /etc/msmtprc`.
- Delivery failure (`smtp status 535`): wrong SMTP credentials — fix in `/etc/msmtprc`.
- TLS failure (`TLS not available`): the provider may require `tls_starttls on` or port 465 (`tls_starttls off`, `tls on`).

---

## 13. `/var/www/` permissions

**Check:**
```bash
stat -c '%U:%G %a %n' /var/www /var/www/html
sudo find /var/www -type f -perm -o+w
sudo find /var/www -type d -perm -o+w ! -path '*/uploads/*' ! -path '*/cache/*'
```
**Expected:**
- `/var/www` and `/var/www/html` owned by `www-data:www-data` (or `root:root` for `/var/www` itself), mode `755`.
- No world-writable files anywhere under `/var/www`.
- No world-writable directories except inside known-safe subpaths (`uploads/`, `cache/`, `tmp/`).

**Remediation — normalise permissions on every webroot:**
```bash
sudo chown -R www-data:www-data /var/www/html
sudo find /var/www/html -type d -exec chmod 755 {} \;
sudo find /var/www/html -type f -exec chmod 644 {} \;
sudo find /var/www/html -type f -perm -o+w -exec chmod o-w {} \;
```

For sites that need to write to `uploads/` or `cache/`, grant the group write bit rather than world write:

```bash
sudo chown -R www-data:www-data /var/www/html/<site>/uploads
sudo chmod -R g+w /var/www/html/<site>/uploads
```

---

## 14. Sources

- Atef, Ghada. *Mastering Ubuntu: A Comprehensive Guide to Linux's Favorite.* 2023 — Chapter V (System Administration) and Chapter VI (Ubuntu for Servers).
- Canonical. *Ubuntu Server Guide — Linux 20.04 LTS (Focal).* 2020 — security, networking, web servers, and systemd service-management chapters.
- `man 5 sshd_config`, `man 8 ufw`, `man 8 fail2ban-client`, `man 8 unattended-upgrade`, `man 1 certbot`, `man 1 rclone`, `man 1 msmtp`.
- Debian/Ubuntu packaging defaults in `/etc/ssh/sshd_config`, `/etc/fail2ban/jail.conf`, `/etc/apt/apt.conf.d/50unattended-upgrades`.
