# Security Audit — 10 Layer Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

The complete read-only 10-layer security audit for a modern Ubuntu/Debian
server (22.04 / 24.04, Nginx + PHP-FPM + MySQL/MariaDB + Redis). Work through
every layer in order — each command is safe to run on a production box
because nothing here mutates state. For every finding, classify it as
**CRITICAL**, **HIGH**, **MEDIUM**, **LOW**, **INFO**, or **PASS** using the
thresholds documented under each layer. Once the scan is done, hand the
findings over to `linux-server-hardening` to fix them.

## Table of contents

- [How to score a finding](#how-to-score-a-finding)
- [Layer 1: System and kernel](#layer-1-system-and-kernel)
- [Layer 2: Users and authentication](#layer-2-users-and-authentication)
- [Layer 3: Network exposure](#layer-3-network-exposure)
- [Layer 4: Firewall](#layer-4-firewall)
- [Layer 5: Web server](#layer-5-web-server)
- [Layer 6: Databases](#layer-6-databases)
- [Layer 7: Filesystem](#layer-7-filesystem)
- [Layer 8: Intrusion detection and monitoring](#layer-8-intrusion-detection-and-monitoring)
- [Layer 9: Backup integrity](#layer-9-backup-integrity)
- [Layer 10: Packages and software inventory](#layer-10-packages-and-software-inventory)
- [Supplementary: LSM, GRUB, file attributes](#supplementary-lsm-grub-file-attributes)
- [Severity thresholds at a glance](#severity-thresholds-at-a-glance)
- [Sources](#sources)

## How to score a finding

Every finding is written as one line:

```
[SEVERITY] Short description (host, command that detected it)
```

Use this fixed rubric across all 10 layers:

| Rating    | Meaning                                                | Typical example                                           |
|-----------|--------------------------------------------------------|-----------------------------------------------------------|
| CRITICAL  | Exploitable right now with no further steps.            | MySQL listening on `0.0.0.0:3306`, ASLR disabled.         |
| HIGH      | Serious risk — must fix within 24h.                     | UFW disabled, SSH permits passwords, TLS 1.0 accepted.    |
| MEDIUM    | Should fix soon, not a direct break-in path alone.      | `fail2ban` inactive, 20+ pending security updates.        |
| LOW       | Best-practice gap, minor defense-in-depth loss.         | X11Forwarding enabled, no GRUB password.                  |
| INFO      | Informational, no action required.                      | AIDE not installed on a dev box.                          |
| PASS      | Setting is correct.                                      | — (only count these, don't print each).                  |

Keep one scratchpad file per layer while the audit runs and aggregate the
totals at the end. The goal is a single scored report the operator can act
on, not a running commentary.

---

## Layer 1: System and kernel

**What it checks:** kernel version, kernel-hardening sysctls, pending kernel
and security updates, ASLR, `dmesg` and pointer restrictions, core
bootloader/init facts. These settings are the OS-level blast door — if they
fail, every upper layer is weaker than it looks.

### Commands

```bash
# Kernel release + distribution
uname -r
lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME

# Uptime (flag boxes that have gone months without a reboot for a kernel CVE)
uptime -p

# Core kernel-hardening sysctls
sysctl kernel.randomize_va_space        # expect 2 (full ASLR)
sysctl kernel.dmesg_restrict            # expect 1
sysctl kernel.kptr_restrict             # expect 2
sysctl kernel.yama.ptrace_scope         # expect 1 or higher
sysctl kernel.sysrq                     # expect 0 on servers
sysctl fs.suid_dumpable                 # expect 0
sysctl fs.protected_hardlinks           # expect 1
sysctl fs.protected_symlinks            # expect 1

# Network stack sysctls
sysctl net.ipv4.tcp_syncookies             # expect 1
sysctl net.ipv4.conf.all.rp_filter         # expect 1
sysctl net.ipv4.conf.all.accept_redirects  # expect 0
sysctl net.ipv4.conf.all.send_redirects    # expect 0
sysctl net.ipv4.conf.all.accept_source_route  # expect 0
sysctl net.ipv4.conf.all.log_martians      # expect 1
sysctl net.ipv4.icmp_echo_ignore_broadcasts   # expect 1
sysctl net.ipv6.conf.all.accept_redirects  # expect 0

# Pending updates
sudo apt-get -s upgrade 2>/dev/null | grep -E '^[0-9]+ upgraded' | head -1
apt list --upgradable 2>/dev/null | grep -ci security

# Unattended-upgrades status
systemctl is-enabled unattended-upgrades 2>/dev/null
systemctl is-active unattended-upgrades 2>/dev/null
grep -E 'Unattended-Upgrade::Allowed-Origins|Unattended-Upgrade::Automatic-Reboot' \
    /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null

# Did the running kernel get replaced on disk? (reboot required)
ls /var/run/reboot-required 2>/dev/null && echo "REBOOT REQUIRED"
```

### Severity thresholds

| Finding | Severity |
|---|---|
| `kernel.randomize_va_space` is `0` or `1` | **CRITICAL** — ASLR off disables a core userspace exploit mitigation. |
| `kernel.kptr_restrict=0` on a shared box | **HIGH** — kernel pointer leaks help ROP. |
| `kernel.dmesg_restrict=0` with a multi-user server | **HIGH** — kernel log exposes addresses. |
| `net.ipv4.tcp_syncookies=0` | **HIGH** — SYN flood protection off. |
| `net.ipv4.conf.all.rp_filter=0` | **HIGH** — reverse path filtering off, IP spoofing easier. |
| >20 pending security updates | **HIGH** |
| 5–20 pending security updates | **MEDIUM** |
| `unattended-upgrades` disabled | **MEDIUM** |
| Reboot required marker present >7 days | **MEDIUM** — kernel on disk newer than running kernel. |
| `kernel.sysrq=1` on a production server | **LOW** |
| `kernel.yama.ptrace_scope=0` | **LOW** |

## Layer 2: Users and authentication

**What it checks:** who can log in, how they authenticate, what SSH allows,
who has `sudo`, and whether any account is a landmine (UID 0 duplicate, empty
password, world-readable key). Every compromise I have walked onto a server
to clean up eventually traces to one of the checks in this layer.

### Commands

```bash
# Extra UID-0 accounts (only root should appear)
awk -F: '$3 == 0 {print $1}' /etc/passwd

# Empty-password accounts
sudo awk -F: '$2 == "" {print $1}' /etc/shadow

# Duplicate UIDs and duplicate usernames
awk -F: '{print $3}' /etc/passwd | sort | uniq -d
awk -F: '{print $1}' /etc/passwd | sort | uniq -d

# Users with interactive shells
grep -E '/bin/(ba|)sh|/bin/zsh' /etc/passwd | cut -d: -f1

# Members of privileged groups
grep -E '^(sudo|admin|adm|wheel):' /etc/group

# Password aging policy
grep -E '^PASS_MAX_DAYS|^PASS_MIN_DAYS|^PASS_WARN_AGE|^ENCRYPT_METHOD' /etc/login.defs

# Per-user password status and aging
sudo passwd -S -a 2>/dev/null | awk '$2 !~ /^L$|^NP$/ {print}'
sudo chage -l root

# Effective SSH daemon config (sshd -T reads all *.d/*.conf drop-ins)
sudo sshd -T 2>/dev/null | grep -iE \
    'permitrootlogin|passwordauthentication|permitemptypassword|pubkeyauth|\
maxauthtries|x11forwarding|allowusers|allowgroups|protocol|banner|\
clientaliveinterval|usepam|allowagentforwarding|allowtcpforwarding|\
permittunnel|maxsessions|logingracetime'

# Every authorized_keys file on the box
sudo find /home /root -name authorized_keys 2>/dev/null -exec \
    sh -c 'echo "=== $1 ==="; awk "{print \$1, \$3, \$NF}" "$1"' _ {} \;

# Recent login patterns and failed attempts
last -n 20 -F
lastb -n 20 2>/dev/null | head
sudo faillock 2>/dev/null | head
```

### Severity thresholds

| Finding | Severity |
|---|---|
| Any non-`root` account with UID 0 | **CRITICAL** |
| Any account with empty password hash in `/etc/shadow` | **CRITICAL** |
| `PasswordAuthentication yes` reachable from the internet | **CRITICAL** |
| `PermitRootLogin yes` (not `no` and not `prohibit-password`) | **HIGH** |
| `PermitEmptyPasswords yes` | **CRITICAL** |
| SSH banner absent and AllowUsers/AllowGroups not set | **LOW** |
| `MaxAuthTries > 4` | **LOW** |
| `ClientAliveInterval` unset or > 600 | **LOW** |
| `X11Forwarding yes` | **LOW** |
| `PASS_MAX_DAYS 99999` for interactive users on a shared host | **MEDIUM** |
| An account never locked with no password change in >365 days | **MEDIUM** |
| `authorized_keys` world-readable (mode > 600) | **HIGH** |
| Orphaned authorized_keys (user removed but file remains) | **MEDIUM** |
| Duplicate UID or duplicate username | **HIGH** |

## Layer 3: Network exposure

**What it checks:** every TCP/UDP port the kernel is currently listening on,
the process behind it, and — most importantly — the bind address. A service
on `127.0.0.1` is invisible to attackers; the same service on `0.0.0.0` is
the first thing nmap finds.

### Commands

```bash
# Everything listening, process names included (needs root)
sudo ss -tulnp

# Just the TCP listeners in sorted order
sudo ss -tlnp | sort

# Dangerous data stores — must all be 127.0.0.1 or ::1
sudo ss -tlnp | grep -E ':3306|:5432|:6379|:11211|:27017|:9200|:2379'

# All public listeners (v4 + v6)
sudo ss -tlnp | awk '$4 ~ /^0\.0\.0\.0:|^\*:|^\[::\]:/ {print $4, $NF}'

# Cross-check with lsof for anything not in a unit
sudo lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null

# What ports does the running nftables/iptables actually let in?
sudo nft list ruleset 2>/dev/null | head -40
sudo iptables -S 2>/dev/null | head -20

# Outbound baseline — any process beaconing that shouldn't be?
sudo ss -tnp state established | grep -v '127.0.0.1\|::1' | head -20
```

### Severity thresholds

| Finding | Severity |
|---|---|
| MySQL / MariaDB / PostgreSQL / Redis / Mongo / Memcached / Elasticsearch / etcd on `0.0.0.0` | **CRITICAL** |
| A development tool (`webpack`, `vite`, `nodemon`) listening publicly | **HIGH** |
| Unknown high port with unknown process listening | **HIGH** — investigate. |
| Node/PM2/gunicorn on `0.0.0.0` instead of `127.0.0.1` behind Nginx | **MEDIUM** |
| IPv6 listener on a service that only needs IPv4 | **LOW** |
| Established outbound connection to unexpected CIDR | **MEDIUM** — could be legitimate SaaS, could be C2. |

## Layer 4: Firewall

**What it checks:** whether UFW (or nft directly) is enabled, what its
default policy is, and which rules are loaded. The only acceptable default
policy on a public server is `deny (incoming)`.

### Commands

```bash
# UFW status
sudo ufw status verbose

# Default policy (must show deny(incoming))
sudo ufw status verbose | grep -i "Default:"

# Rule count
sudo ufw status numbered | grep -c '^\['

# Fallback: raw nftables and iptables views
sudo nft list ruleset 2>/dev/null
sudo iptables -L INPUT -n -v 2>/dev/null | head -20
sudo iptables -L FORWARD -n -v 2>/dev/null | head

# Is anything on the box manipulating nftables outside UFW?
systemctl list-units --type=service --state=running | \
    grep -iE 'firewalld|nftables|iptables-persistent|shorewall'
```

### Severity thresholds

| Finding | Severity |
|---|---|
| `ufw status` = `inactive` and no nftables rules loaded | **CRITICAL** |
| Default incoming policy `allow` | **HIGH** |
| `ALLOW Anywhere` on 3306/5432/6379/27017 | **CRITICAL** |
| `ALLOW Anywhere` on 22/tcp (SSH) when a jump host is available | **LOW** |
| Unexplained `ALLOW` rule (unknown port) | **MEDIUM** |
| firewalld and UFW both active | **MEDIUM** — rule precedence is confusing. |
| FORWARD default is `ACCEPT` on a non-router host | **HIGH** |

## Layer 5: Web server

**What it checks:** Nginx/Apache TLS configuration, `server_tokens`, security
headers, PHP-FPM exposure, expired certificates, and dangerous PHP ini
settings. This is where a misconfig most often gets found by automated
scanners within 24h of the server going live.

### Commands

```bash
# Nginx — full dumped config
sudo nginx -T 2>/dev/null | grep -E \
    'server_tokens|ssl_protocols|ssl_ciphers|ssl_prefer_server|add_header|ssl_certificate'

# Certificate expiry (certbot-managed)
sudo certbot certificates 2>/dev/null

# Manual cert expiry probe
for d in $(sudo certbot certificates 2>/dev/null | awk '/Domains/ {for(i=2;i<=NF;i++) print $i}'); do
    echo "=== $d ==="
    echo | openssl s_client -servername "$d" -connect "$d":443 2>/dev/null | \
        openssl x509 -noout -dates
done

# Reject TLS 1.0 / 1.1 must fail
echo | openssl s_client -connect localhost:443 -tls1   2>&1 | grep -E 'handshake|alert' | head -2
echo | openssl s_client -connect localhost:443 -tls1_1 2>&1 | grep -E 'handshake|alert' | head -2
echo | openssl s_client -connect localhost:443 -tls1_2 2>&1 | grep -E 'handshake|alert' | head -2

# Security headers (check from outside too)
curl -sI https://localhost --resolve localhost:443:127.0.0.1 -k | grep -iE \
    'strict-transport|x-frame-options|x-content-type|content-security|referrer-policy'

# Apache equivalent
sudo apache2ctl -M 2>/dev/null | grep -i ssl
sudo apache2ctl -S 2>/dev/null | head -20

# PHP hot-take INI values
for k in expose_php display_errors allow_url_include allow_url_fopen \
         session.cookie_secure session.cookie_httponly session.use_strict_mode \
         session.cookie_samesite disable_functions open_basedir upload_tmp_dir; do
    printf '%-30s %s\n' "$k" "$(php -r "echo ini_get('$k');")"
done

# PHP-FPM pool identity
grep -E '^user|^group|^listen' /etc/php/*/fpm/pool.d/www.conf 2>/dev/null
```

### Severity thresholds

| Finding | Severity |
|---|---|
| Certificate expires in <7 days | **CRITICAL** |
| Certificate expires in <30 days | **HIGH** |
| TLS 1.0 or TLS 1.1 accepted | **HIGH** |
| `ssl_protocols` allows SSLv3 | **CRITICAL** |
| `server_tokens on` or Apache `ServerTokens Full` | **HIGH** — exposes version. |
| PHP `expose_php=On` | **HIGH** |
| PHP `display_errors=On` | **HIGH** — leaks paths and DB creds in stack traces. |
| PHP `allow_url_include=On` | **CRITICAL** — RFI enabled. |
| PHP `disable_functions` empty and webapp uses user input to shell out | **HIGH** |
| No `Strict-Transport-Security` header | **MEDIUM** |
| No `X-Frame-Options` and no frame-ancestors CSP | **MEDIUM** |
| PHP-FPM pool running as `root` or `nobody` | **HIGH** |

## Layer 6: Databases

**What it checks:** MySQL/MariaDB, PostgreSQL, Redis, and MongoDB for the
three things that get databases ransomed: wrong bind address, anon/empty
password accounts, and wide-open authentication rules.

### Commands

```bash
# ---- MySQL / MariaDB ----
sudo grep -rE '^bind-address|^skip-networking' \
    /etc/mysql/mysql.conf.d/ /etc/mysql/mariadb.conf.d/ 2>/dev/null

# Anonymous or empty-password users
sudo mysql -e "SELECT user,host,authentication_string FROM mysql.user \
    WHERE user='' OR authentication_string='';" 2>/dev/null

# User grants overview (watch for *.* to % hosts)
sudo mysql -e "SELECT user,host FROM mysql.user ORDER BY user;" 2>/dev/null

# test DB should not exist
sudo mysql -e "SHOW DATABASES;" 2>/dev/null | grep -E '^(test|information)$'

# ---- PostgreSQL ----
sudo -u postgres psql -c '\du' 2>/dev/null
grep -vE '^\s*#|^\s*$' /etc/postgresql/*/main/pg_hba.conf 2>/dev/null
grep -E '^listen_addresses' /etc/postgresql/*/main/postgresql.conf 2>/dev/null

# ---- Redis ----
grep -E '^bind|^requirepass|^protected-mode|^rename-command' \
    /etc/redis/redis.conf 2>/dev/null
redis-cli ping 2>/dev/null   # should require auth

# ---- MongoDB ----
grep -E 'bindIp|authorization' /etc/mongod.conf 2>/dev/null
```

### Severity thresholds

| Finding | Severity |
|---|---|
| `bind-address = 0.0.0.0` on MySQL/MariaDB | **CRITICAL** |
| `listen_addresses = '*'` on PostgreSQL + `0.0.0.0/0 trust` in `pg_hba.conf` | **CRITICAL** |
| Redis `bind 0.0.0.0` + no `requirepass` | **CRITICAL** |
| Redis `protected-mode no` with no password | **CRITICAL** |
| MongoDB `bindIp: 0.0.0.0` with `authorization: disabled` | **CRITICAL** |
| Any MySQL user with empty password | **CRITICAL** |
| `test` database still present | **MEDIUM** |
| PostgreSQL `md5` lines in `pg_hba.conf` (should be `scram-sha-256`) | **MEDIUM** |
| MySQL `root@%` account exists | **HIGH** |
| Redis `CONFIG`, `FLUSHDB`, `FLUSHALL` not renamed | **MEDIUM** |

## Layer 7: Filesystem

**What it checks:** world-writable files in `/var/www`, unexpected SUID/SGID
binaries, credential file permissions, orphan files, and sticky bit on
shared directories. The goal is a clean baseline — every SUID should be on
your shortlist of known-good binaries.

### Commands

```bash
# World-writable files under the web root
find /var/www -type f -perm -0002 2>/dev/null

# World-writable directories anywhere (excluding known sticky /tmp)
find / -xdev -type d -perm -0002 ! -perm -1000 \
    -not -path '/proc/*' -not -path '/sys/*' -not -path '/dev/*' 2>/dev/null

# SUID/SGID hunt (minus the expected list)
find / -xdev -perm /6000 -type f 2>/dev/null | grep -vE \
    '/(sudo|passwd|su|mount|umount|ping|ping6|traceroute6\.iputils|crontab|at|\
newgrp|chsh|chfn|gpasswd|pkexec|chage|expiry|unix_chkpwd|ssh-agent|dbus-daemon-launch-helper|\
pam_timestamp_check|fusermount3|utempter|mtr-packet|suexec)$'

# Credential files must be mode 600
stat -c '%a %U:%G %n' \
    ~/.mysql-backup.cnf ~/.backup-encryption-key ~/.pgpass \
    ~/.config/rclone/rclone.conf ~/.aws/credentials 2>/dev/null

# System file permissions
stat -c '%a %U:%G %n' \
    /etc/shadow /etc/gshadow /etc/passwd /etc/group \
    /etc/ssh/sshd_config /etc/sudoers /boot/grub/grub.cfg

# Orphaned files (no user/group)
find /var/www /home /etc -xdev \( -nouser -o -nogroup \) 2>/dev/null | head -20

# Immutable critical files
lsattr /etc/passwd /etc/shadow /etc/sudoers /etc/resolv.conf 2>/dev/null

# Sticky bit verification
stat -c '%a %n' /tmp /var/tmp   # expect 1777
```

### Severity thresholds

| Finding | Severity |
|---|---|
| World-writable file under `/var/www` | **HIGH** |
| World-writable directory anywhere without sticky bit | **HIGH** |
| `/etc/shadow` not 640 root:shadow | **HIGH** |
| `/etc/sudoers` not 440 root:root | **HIGH** |
| Credential file not 600 | **HIGH** |
| Unknown SUID binary in user's `$HOME` or `/tmp` | **CRITICAL** |
| Unknown SUID binary under `/usr/local/bin` | **HIGH** — investigate. |
| Orphan files in `/var/www` | **MEDIUM** |
| `/tmp` missing sticky bit | **HIGH** |

## Layer 8: Intrusion detection and monitoring

**What it checks:** whether fail2ban is actively banning, AIDE has been
initialized, auditd is running with rules loaded, and something is reading
logs. These tools do not prevent an attack — they make sure you notice the
one that slips past the rest of the stack.

### Commands

```bash
# fail2ban
systemctl is-active fail2ban
sudo fail2ban-client status 2>/dev/null
sudo fail2ban-client status sshd 2>/dev/null | grep -E 'Currently|Total'
sudo awk '/Ban /{print $NF}' /var/log/fail2ban.log 2>/dev/null | sort | uniq -c | sort -rn | head

# AIDE
dpkg -l aide 2>/dev/null | grep ^ii
ls -la /var/lib/aide/aide.db 2>/dev/null
ls /etc/cron.daily/ | grep -i aide

# auditd
systemctl is-active auditd
sudo auditctl -l 2>/dev/null | wc -l     # expect > 5
sudo auditctl -s 2>/dev/null | head

# Log shippers / remote syslog
systemctl is-active rsyslog 2>/dev/null
grep -v '^#\|^$' /etc/rsyslog.d/*.conf 2>/dev/null | grep -E '@@?[0-9a-zA-Z]' | head

# logwatch / logcheck
dpkg -l 2>/dev/null | grep -E '^ii +(logwatch|logcheck) '
```

### Severity thresholds

| Finding | Severity |
|---|---|
| fail2ban installed but inactive | **HIGH** |
| fail2ban running with 0 jails | **HIGH** |
| fail2ban running with only `sshd` on a web host | **MEDIUM** |
| AIDE not installed on a production host | **MEDIUM** |
| AIDE installed but database missing | **MEDIUM** |
| auditd inactive on a compliance-regulated host | **HIGH** |
| auditd active but <5 rules loaded | **MEDIUM** |
| No remote log shipping on a production host | **MEDIUM** — attacker can wipe logs locally. |

## Layer 9: Backup integrity

**What it checks:** that backups exist, are recent, are encrypted, live
off-host, and the credentials to talk to the remote are 600. A missing
backup does not get you owned — it gets you fired after you get owned.

### Commands

```bash
# Scheduled jobs that mention backup/rclone/restic/borg
crontab -l 2>/dev/null | grep -iE 'backup|rclone|restic|borg|duplicity'
sudo crontab -l 2>/dev/null | grep -iE 'backup|rclone|restic|borg|duplicity'
sudo ls /etc/cron.d/ /etc/cron.daily/ /etc/cron.hourly/ | grep -iE 'backup|rclone|restic|borg'

# systemd timers
systemctl list-timers --all 2>/dev/null | grep -iE 'backup|rclone|restic|borg'

# Recent backup artifacts (last 24h)
find ~/backups /var/backups -type f -mtime -1 2>/dev/null | head -20
find ~/backups /var/backups -name "*.gpg" -o -name "*.age" -o -name "*.enc" 2>/dev/null | head

# Remote storage reachability
rclone about gdrive: 2>/dev/null | head -3 || echo "rclone: gdrive unreachable"
restic --repo "$RESTIC_REPOSITORY" snapshots 2>/dev/null | tail -5

# Credential file presence + mode
for f in ~/.mysql-backup.cnf ~/.backup-encryption-key ~/.config/rclone/rclone.conf ~/.pgpass; do
    if [ -f "$f" ]; then
        printf 'OK   %s %s\n' "$(stat -c '%a' "$f")" "$f"
    else
        printf 'MISS %s\n' "$f"
    fi
done
```

### Severity thresholds

| Finding | Severity |
|---|---|
| No backup job scheduled anywhere | **CRITICAL** |
| Last backup artifact older than 48h on a daily-schedule host | **HIGH** |
| Backups stored only on the same host | **HIGH** |
| Backups unencrypted (`.sql.gz` with no `.gpg`/`.age`) | **HIGH** |
| Backup credential file missing | **HIGH** — backup job will fail silently. |
| Backup credential file mode not 600 | **HIGH** |
| Remote storage unreachable (token expired) | **HIGH** |
| Restore has never been tested | **MEDIUM** |

## Layer 10: Packages and software inventory

**What it checks:** what the package manager knows. Pending updates,
unexpected services, third-party PPAs, snaps, and anything `apt` considers
obsolete. This is the layer that catches "there's an old Node.js on this
box I forgot about".

### Commands

```bash
# Total upgradable packages
apt list --upgradable 2>/dev/null | tail -n +2 | wc -l

# Security updates only
sudo apt-get -s upgrade 2>/dev/null | grep -i security | wc -l

# Obsolete / locally-installed packages
apt list --installed 2>/dev/null | grep -i local

# Third-party sources
ls /etc/apt/sources.list.d/ 2>/dev/null
grep -v '^\s*#\|^\s*$' /etc/apt/sources.list.d/*.list 2>/dev/null | head -30

# All third-party repos in one view (modern deb822 format)
ls /etc/apt/sources.list.d/*.sources 2>/dev/null

# Running services — any you don't recognize?
systemctl list-units --type=service --state=running --no-pager --plain 2>/dev/null | \
    awk '{print $1}' | grep -vE \
    'systemd|cron|ssh|ufw|nginx|apache|mysql|mariadb|postgresql|php|redis|\
fail2ban|networkd|resolved|timesyncd|dbus|polkit|unattended-upgrades|chrony|auditd'

# Snaps on a server host (often unexpected)
snap list 2>/dev/null

# Lynis quick scan (optional but highly useful)
command -v lynis >/dev/null 2>&1 && \
    sudo lynis audit system --quick 2>/dev/null | grep -E 'Hardening index|Warning|Suggestion' | head -15
```

### Severity thresholds

| Finding | Severity |
|---|---|
| >20 pending security updates | **HIGH** |
| 5–20 pending security updates | **MEDIUM** |
| >50 total pending updates and server has not rebooted in >90 days | **HIGH** |
| Third-party PPA from an unknown maintainer | **MEDIUM** |
| Running service with no unit file in `/lib/systemd/system` | **MEDIUM** — investigate. |
| `snap` daemon running on a minimal server | **LOW** |
| Lynis hardening index <60 | **HIGH** |
| Lynis hardening index 60–75 | **MEDIUM** |

## Supplementary: LSM, GRUB, file attributes

These layers are not in the main 10 but are part of the full deep audit.

### LSM / mandatory access control

```bash
# AppArmor
systemctl is-active apparmor 2>/dev/null
sudo aa-status 2>/dev/null | head -20
sudo grep 'DENIED' /var/log/audit/audit.log /var/log/kern.log 2>/dev/null | tail -10

# SELinux (on Ubuntu only if explicitly installed)
getenforce 2>/dev/null
```

| Finding | Severity |
|---|---|
| AppArmor disabled on a production Ubuntu host | **HIGH** |
| AppArmor running with 0 profiles in enforce mode | **MEDIUM** |
| Recent AppArmor DENIED events not investigated | **MEDIUM** |

### GRUB / early boot

```bash
stat -c '%a %U:%G %n' /boot/grub/grub.cfg   # expect 600 root:root
grep -i password /etc/grub.d/40_custom /boot/grub/grub.cfg 2>/dev/null
```

| Finding | Severity |
|---|---|
| `grub.cfg` world-readable on a shared/physical host | **MEDIUM** |
| No GRUB password on a physically accessible box | **LOW** |

### File attributes

```bash
lsattr /etc/passwd /etc/shadow /etc/group /etc/sudoers /etc/resolv.conf 2>/dev/null
```

Presence of the `i` (immutable) or `a` (append-only) attribute is usually a
PASS for hardened hosts. On a compromised host, an attacker may set `+i` on
their backdoor to stop you from deleting it — so always cross-check with the
SUID hunt in Layer 7.

## Severity thresholds at a glance

A compact operator cheat sheet to keep open while writing the report:

| Layer | Single biggest CRITICAL trigger | Single biggest HIGH trigger |
|---|---|---|
| 1 Kernel     | ASLR disabled                          | >20 security updates pending            |
| 2 Auth       | Extra UID-0 or empty password          | `PermitRootLogin yes`                   |
| 3 Network    | DB on `0.0.0.0`                        | Dev tool publicly exposed               |
| 4 Firewall   | UFW inactive                           | Default `allow incoming`                |
| 5 Web        | Cert expiring <7 days                  | TLS 1.0/1.1 accepted                    |
| 6 Database   | Redis `bind 0.0.0.0` no password       | `root@%` MySQL account                  |
| 7 FS         | SUID binary in `$HOME` or `/tmp`       | `/etc/shadow` not 640                   |
| 8 IDS        | —                                      | fail2ban down                           |
| 9 Backup     | No backup job at all                   | Backup >48h old                         |
| 10 Packages  | —                                      | Lynis index <60                         |

## Optional fast path

If the `sk-*` convenience scripts are installed, `sudo sk-audit` runs a
read-only wrapper over the same commands as this file and prints a
PASS/WARN/FAIL report with a score. The 10-layer manual procedure above is
the source of truth — the script is only a speedup.

## Sources

- *Mastering Linux Security and Hardening*, Donald A. Tevault, 3rd Edition,
  Packt Publishing — Chapters 2 (Securing User Accounts), 3 (Securing Normal
  User Accounts), 4–5 (Firewall), 6 (SSH Hardening), 8 (Mastering DAC), 10
  (MAC with AppArmor and SELinux), 11 (Kernel Hardening with sysctl), 12
  (Scanning, Auditing, and Hardening), 13 (Logging and Log Security), 14
  (Vulnerability Scanning and Intrusion Detection).
- *Practical Linux Security Cookbook*, Tajinder Kalsi, Packt Publishing —
  recipes for file permission auditing, SUID/SGID hunting, password aging,
  and user activity monitoring.
- *Ubuntu Server Guide*, Canonical (Focal 20.04 LTS, applies to 22.04/24.04)
  — "Security" chapter covering UFW, SSH, users/groups, AppArmor, console
  security, and updates.
- CIS Ubuntu Linux 22.04 LTS Benchmark — the numeric thresholds in the
  severity tables are aligned to Level 1 Server recommendations where they
  exist.
- Upstream manual pages: `sshd_config(5)`, `sysctl(8)`, `ss(8)`, `ufw(8)`,
  `mysql(1)`, `redis.conf(5)`, `fail2ban-client(1)`, `aide.conf(5)`,
  `auditctl(8)`.
