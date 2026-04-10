# AIDE and auditd

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This file is the deep reference for the two kernel-level intrusion
detection tools every production Ubuntu/Debian server should run: **AIDE**
(Advanced Intrusion Detection Environment — file integrity checks) and
**auditd** (kernel-level system call auditing). Both use only standard
Ubuntu packages — no `sk-*` scripts required.

- **AIDE** answers: *which files have changed since we last knew they were
  good?* It runs on a schedule, compares filesystem state against a stored
  database, and reports drift.
- **auditd** answers: *who did what, and when?* It hooks into the kernel
  audit subsystem to log syscalls matching rules you define — file writes,
  process execution, privilege escalation.

Together they cover both the "after the fact" and "as it happened" views
of server compromise.

## Table of contents

- [When to use which tool](#when-to-use-which-tool)
- [AIDE: install and initialize](#aide-install-and-initialize)
- [AIDE: tuning /etc/aide/aide.conf](#aide-tuning-etcaideaideconf)
- [AIDE: running a check](#aide-running-a-check)
- [AIDE: reading the report](#aide-reading-the-report)
- [AIDE: updating the baseline after legitimate changes](#aide-updating-the-baseline-after-legitimate-changes)
- [AIDE: scheduling nightly checks with mail](#aide-scheduling-nightly-checks-with-mail)
- [auditd: install and enable](#auditd-install-and-enable)
- [auditd: writing rules in /etc/audit/rules.d/](#auditd-writing-rules-in-etcauditrulesd)
- [auditd: the rule catalogue](#auditd-the-rule-catalogue)
- [auditd: reading the log](#auditd-reading-the-log)
- [auditd: rotation and performance](#auditd-rotation-and-performance)
- [Integrating with fail2ban and alerting](#integrating-with-fail2ban-and-alerting)
- [Sources](#sources)

---

## When to use which tool

| Question | Tool |
|---|---|
| "Has anyone modified `/etc/passwd` since yesterday?" | AIDE (periodic) or auditd (real-time) |
| "Who added a new SUID binary to `/usr/local/bin`?" | auditd (catches the event) |
| "Did `/bin/ls` get replaced with a trojan?" | AIDE (catches the changed hash) |
| "Who ran `sudo` at 03:12 this morning?" | auditd |
| "What files changed on `/etc` this week?" | AIDE (fast summary) |
| "What process wrote to `/var/www/html/index.php`?" | auditd |

Rule of thumb: **AIDE for drift, auditd for attribution.** Use both.

---

## AIDE: install and initialize

### Install

```bash
sudo apt install aide aide-common
```

The package installs:
- `/usr/bin/aide` — the checker binary.
- `/etc/aide/aide.conf` — the main config.
- `/etc/aide/aide.conf.d/` — drop-in snippets that `update-aide.conf`
  assembles into the active config.
- `/var/lib/aide/aide.db` — the trusted baseline (created after init).

### Initialize the database

After install, run `aideinit` to build the initial database. This takes
1-10 minutes depending on server size — AIDE hashes every file in the
watched paths.

```bash
sudo aideinit

# When it finishes, move the "new" database into place as the trusted one:
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

**Critical:** run `aideinit` on a server you *know* is clean — right after
provisioning, before it's ever exposed to the internet. If you initialize
on a compromised server, you're just baselining the compromise as "normal."

### Smoke test

```bash
sudo aide --check
```

Expected: "AIDE found NO differences between database and filesystem."

Touch a file and re-check:

```bash
sudo touch /etc/test-aide
sudo aide --check
# Expected: report showing /etc/test-aide as added
sudo rm /etc/test-aide
```

---

## AIDE: tuning /etc/aide/aide.conf

The Ubuntu package splits config into two parts:

1. `/etc/aide/aide.conf` — the main entry point (usually untouched).
2. `/etc/aide/aide.conf.d/` — drop-in fragments. Each adds rules for a
   specific area (ssh, sudoers, web root, logs, etc.).

When you change anything, regenerate the active config:

```bash
sudo update-aide.conf
```

### Rule syntax

A rule line looks like:

```
/etc/ssh/    NORMAL
!/var/log/mail.log
/var/log/    Logs
```

- **`/path`** — the directory or file to watch.
- **`ModeName`** — a named set of checks to apply. Common modes:
  - `NORMAL` — permissions, owner, group, size, mtime, ctime, hashes.
  - `Logs` — logs rotate and grow; check perms and owner but not size/mtime/hashes.
  - `ConfFiles` — content must not change; strict.
  - `DataDir` — dirs; check structure, not every file.
- **`!/path`** — **ignore** this path. Prefixed with `!`.
- **`=path`** — check only this directory, not recursively.

### Define your own mode

Put a custom mode definition at the top of a drop-in:

```bash
sudo tee /etc/aide/aide.conf.d/99-linux-skills > /dev/null <<'EOF'
# Strict mode for content-critical files
ContentStrict = p+u+g+n+s+b+m+c+md5+sha256

# Loose mode for directories that legitimately change
Structure = p+u+g+ftype

# Rules
/etc/ssh/sshd_config ContentStrict
/etc/ssh/sshd_config.d/ ContentStrict
/etc/sudoers ContentStrict
/etc/sudoers.d/ ContentStrict
/etc/passwd ContentStrict
/etc/shadow ContentStrict
/etc/group ContentStrict
/etc/gshadow ContentStrict

/etc/nginx/ ContentStrict
/etc/apache2/ ContentStrict
/etc/php/ ContentStrict
/etc/mysql/ ContentStrict

/usr/bin/ ContentStrict
/usr/sbin/ ContentStrict
/usr/local/bin/ ContentStrict
/usr/local/sbin/ ContentStrict
/bin/ ContentStrict
/sbin/ ContentStrict

# Web root: structure only — content changes legitimately on deploy
/var/www/ Structure

# Watch directory structure, not every file:
/var/log/ Logs

# Ignore dynamic files that would flag every run:
!/var/log/journal
!/var/log/wtmp
!/var/log/btmp
!/var/log/lastlog
!/var/log/nginx/access.log
!/var/log/nginx/error.log
!/var/log/apache2/access.log
!/var/log/apache2/error.log
!/var/log/mysql/
!/var/log/unattended-upgrades/
!/var/lib/php/sessions
!/var/cache
!/var/tmp
!/tmp
!/run
!/proc
!/sys
!/dev
EOF

sudo update-aide.conf
```

### Test the config

```bash
sudo aide --config=/var/lib/aide/aide.conf --config-check
```

---

## AIDE: running a check

```bash
sudo aide --check
```

### Exit codes

| Code | Meaning |
|---|---|
| `0` | No differences. |
| `1..15` | Differences found (see the report for which categories). |
| `16..255` | AIDE error (config, I/O, missing database). |

### Silent mode (for cron)

```bash
sudo aide --check --log-level=warning
```

### Checking a specific path

```bash
sudo aide --check --limit='^/etc/ssh'
```

---

## AIDE: reading the report

A report looks like:

```
AIDE 0.17.4 found differences between database and filesystem!!

Summary:
  Total number of entries:      24817
  Added entries:                1
  Removed entries:              0
  Changed entries:              3

---------------------------------------------------
Added entries:
---------------------------------------------------

f++++++++++++++++: /etc/test-aide

---------------------------------------------------
Changed entries:
---------------------------------------------------

f   ...    .C.. : /etc/ssh/sshd_config
f   ...    .C.. : /etc/sudoers
f>  s...    .C.. : /var/log/wtmp

---------------------------------------------------
Detailed information about changes:
---------------------------------------------------

File: /etc/ssh/sshd_config
  Size     : 3264                            , 3410
  MD5      : abcd...                         , efgh...
  SHA256   : ...                             , ...
```

### Decoding the flag string (`f   ...    .C..`)

Each column is a check result:

- `f` — file type (here: regular file).
- `+` — added.
- `-` — removed.
- `.` — unchanged.
- `C` — content changed (hashes differ).
- `p` — permissions changed.
- `u` — owner changed.
- `g` — group changed.
- `s` — size changed.
- `m` — mtime changed.
- `c` — ctime changed.

The order is mode-dependent. Read the legend at the top of the report.

### Triage flow

1. **Any hash change in `/bin`, `/sbin`, `/usr/bin`, `/usr/sbin`,
   `/usr/local/bin`, `/usr/local/sbin`** → **CRITICAL.** Assume
   compromise. Investigate now. Compare the binary against a fresh copy
   from the package:
   ```bash
   dpkg -S /usr/bin/ssh                          # which package
   debsums /usr/bin/ssh                          # if debsums installed
   md5sum /usr/bin/ssh
   apt download openssh-client
   dpkg-deb -x openssh-client_*.deb /tmp/fresh
   md5sum /tmp/fresh/usr/bin/ssh
   ```
   If they differ, the binary was replaced. Move to incident response.

2. **Any change to `/etc/passwd`, `/etc/shadow`, `/etc/sudoers`,
   `/etc/ssh/sshd_config`** → **HIGH.** Correlate with auditd logs to
   find *who* made the change.

3. **Changes to `/etc/nginx/`, `/etc/php/`, `/etc/mysql/`** → **MEDIUM.**
   Usually legitimate (deployment, config update). Confirm with the
   deployer, then update the baseline.

4. **Changes under `/var/www/`** → expected on deployment. If web root is
   in `Structure` mode, only structure changes report. Anything more means
   reconfigure or investigate.

5. **Changes under `/var/log/`** → should be filtered out via `!` rules.
   If you're still seeing log changes, refine the ignore list.

---

## AIDE: updating the baseline after legitimate changes

After a confirmed-legitimate change (package upgrade, config edit), update
the baseline so the next run starts fresh:

```bash
# Re-initialize
sudo aideinit

# Move the new database into place
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Verify
sudo aide --check
# Expected: no differences
```

Record the update in a log so you know which changes were accepted:

```bash
echo "$(date -Iseconds) aide baseline updated after nginx upgrade" \
    | sudo tee -a /var/log/linux-skills/aide-baseline-updates.log
```

---

## AIDE: scheduling nightly checks with mail

```bash
sudo tee /etc/cron.daily/aide-check > /dev/null <<'EOF'
#!/bin/bash
# Nightly AIDE check — mails the report if changes are found
set -u
REPORT=$(aide --check 2>&1 || true)
COUNT=$(echo "$REPORT" | grep -c '^Added\|^Removed\|^Changed' || true)

if echo "$REPORT" | grep -q "found differences"; then
    echo "$REPORT" | mail -s "AIDE Report $(hostname) $(date +%Y-%m-%d)" root
fi
EOF
sudo chmod +x /etc/cron.daily/aide-check
```

Test:

```bash
sudo /etc/cron.daily/aide-check
```

Ensure `msmtp` or another MTA is configured so root mail actually goes
somewhere a human reads — see `linux-mail-server`.

### Alternative: alert only on critical paths

If you get too many nightly reports, filter for the paths that matter:

```bash
aide --check 2>&1 | grep -E '^(f|d).*: /(etc|bin|sbin|usr/bin|usr/sbin|usr/local/bin|usr/local/sbin)' \
    | mail -s "AIDE CRITICAL $(hostname)" ops@example.com
```

---

## auditd: install and enable

```bash
sudo apt install auditd audispd-plugins
sudo systemctl enable --now auditd
sudo systemctl status auditd --no-pager
```

Key paths:

- `/etc/audit/auditd.conf` — daemon config (log location, rotation, buffer).
- `/etc/audit/rules.d/*.rules` — drop-in rule files; combined into
  `/etc/audit/audit.rules` at daemon start via `augenrules`.
- `/var/log/audit/audit.log` — the log (mode 600, root-only).

### Daemon config essentials

Edit `/etc/audit/auditd.conf`:

```
log_file = /var/log/audit/audit.log
log_format = ENRICHED
max_log_file = 100
max_log_file_action = ROTATE
num_logs = 10
space_left = 500
space_left_action = email
action_mail_acct = root
admin_space_left = 100
admin_space_left_action = halt        # panic if disk full and auditd can't write
disk_full_action = halt
disk_error_action = halt
```

`halt` sounds scary but is the correct posture: if auditd can't write its
log, something is actively going wrong and the server should not continue
processing silently.

For development servers, change to `suspend` or `syslog` during setup,
then `halt` once stable.

---

## auditd: writing rules in /etc/audit/rules.d/

### Rule syntax

File-watch rules:

```
-w <path> -p <perms> -k <key>
```

- `<path>` — file or directory to watch.
- `<perms>` — any combination of `r` (read), `w` (write), `x` (execute),
  `a` (attribute change).
- `<key>` — a short tag you'll use in `ausearch`/`aureport`.

Syscall rules:

```
-a always,exit -F arch=b64 -S <syscall> -k <key>
```

- `always,exit` — audit on every exit from the syscall.
- `arch=b64` — 64-bit. Modern Ubuntu is 64-bit, but if you want to catch
  32-bit binaries as well, duplicate the rule with `arch=b32`.
- `-S <syscall>` — the syscall to trigger on (`execve`, `openat`, `unlink`,
  `chmod`, etc.).
- `-k <key>` — tag.

### Make rules immutable

End the rule file with `-e 2` to lock the rule set until reboot:

```
-e 2
```

Once `-e 2` is active, rule changes require a reboot. This is correct for
production: an attacker with root can't silently disable auditing during
an incident.

During setup, use `-e 0` or omit, and flip to `-e 2` after the rules are
proven stable.

---

## auditd: the rule catalogue

Drop this into `/etc/audit/rules.d/10-linux-skills.rules`:

```
# Delete any existing rules
-D

# Buffer size — larger = less chance of dropped events under heavy load
-b 8192

# Fail mode: 1 = printk, 2 = panic. Use 1 unless this is a high-security box.
-f 1

# ---- Identity and auth ---------------------------------------------------
-w /etc/passwd      -p wa -k identity
-w /etc/shadow      -p wa -k identity
-w /etc/group       -p wa -k identity
-w /etc/gshadow     -p wa -k identity
-w /etc/sudoers     -p wa -k sudoers
-w /etc/sudoers.d/  -p wa -k sudoers

# ---- SSH -----------------------------------------------------------------
-w /etc/ssh/sshd_config    -p wa -k sshd_config
-w /etc/ssh/sshd_config.d/ -p wa -k sshd_config
-w /root/.ssh              -p wa -k ssh_keys
-w /home                   -p wa -k home_dir_changes

# ---- Web config ----------------------------------------------------------
-w /etc/nginx        -p wa -k nginx_config
-w /etc/apache2      -p wa -k apache_config
-w /etc/php          -p wa -k php_config
-w /var/www/html     -p wa -k webroot_changes

# ---- Database config -----------------------------------------------------
-w /etc/mysql        -p wa -k mysql_config
-w /etc/postgresql   -p wa -k postgres_config

# ---- Audit and fail2ban --------------------------------------------------
-w /etc/audit        -p wa -k audit_config
-w /etc/fail2ban     -p wa -k fail2ban_config

# ---- Privileged command execution ----------------------------------------
-a always,exit -F arch=b64 -S execve -F euid=0 -k root_exec
-a always,exit -F arch=b64 -S execve -F path=/usr/bin/sudo -k sudo_exec
-a always,exit -F arch=b64 -S execve -F path=/usr/bin/su -k su_exec

# ---- Time and kernel -----------------------------------------------------
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time_change
-w /etc/localtime -p wa -k time_change
-w /sbin/insmod    -p x -k modules
-w /sbin/modprobe  -p x -k modules
-w /sbin/rmmod     -p x -k modules

# ---- Network config ------------------------------------------------------
-w /etc/netplan    -p wa -k network_config
-w /etc/hosts      -p wa -k network_config
-w /etc/resolv.conf -p wa -k network_config

# ---- Make rules immutable until reboot (enable after testing) ------------
# -e 2
```

Load:

```bash
sudo augenrules --load
sudo systemctl restart auditd
sudo auditctl -l | head -30
```

---

## auditd: reading the log

The log is binary-ish. Use `ausearch` and `aureport`, not `less`.

### ausearch: find events by key

```bash
# Everything tagged sudoers
sudo ausearch -k sudoers -i

# Everything tagged identity in the last hour
sudo ausearch -k identity --start recent -i

# Specific date range
sudo ausearch --start "04/10/2026 14:00:00" --end "04/10/2026 14:30:00" -i

# By file
sudo ausearch -f /etc/passwd -i

# By user ID
sudo ausearch -ua 1000 -i   # audit user ID (the original uid before su/sudo)

# By executable
sudo ausearch -x /usr/bin/sudo -i
```

The `-i` flag interprets numeric IDs into names (`uid=0` → `root`).

### aureport: summaries

```bash
# Overall summary
sudo aureport --summary

# Failed logins
sudo aureport -au --failed

# Successful logins
sudo aureport -au --success

# Executed commands (requires execve syscall rules)
sudo aureport -x --summary

# Files accessed (requires file rules)
sudo aureport -f --summary

# Events by key
sudo aureport -k --summary
```

### Example investigation: who edited /etc/passwd?

```bash
sudo ausearch -f /etc/passwd -i | less
```

Look for:
- `type=SYSCALL` events.
- `exe="/usr/bin/nano"` or similar.
- `comm="nano"` — the command that opened it.
- `auid=1000` — who was logged in (the audit UID survives `su` and `sudo`).
- `success=yes` — did the syscall succeed?

Correlate with the timestamp and `/var/log/auth.log` for the SSH login
that preceded it.

---

## auditd: rotation and performance

### Rotation

Handled by `auditd` itself via `/etc/audit/auditd.conf`:

- `max_log_file = 100` — rotate at 100 MB.
- `num_logs = 10` — keep 10 rotated copies.

Check current log size:

```bash
sudo ls -lh /var/log/audit/
sudo du -sh /var/log/audit/
```

### Performance impact

Watching directories with many small files (e.g. `/var/www/html` for a
WordPress site with 10k files) is expensive. If CPU or I/O goes up after
adding a rule, either narrow the path or drop the rule.

Measure impact:

```bash
sudo auditctl -s             # status, losses, and backlog
```

Watch `lost` — if nonzero, auditd is dropping events. Raise the buffer
(`-b 16384`) or narrow the rules.

### Testing overhead of a rule

```bash
# Baseline
time (for i in $(seq 1 1000); do cat /etc/passwd > /dev/null; done)

# Add a rule on /etc/passwd read
sudo auditctl -w /etc/passwd -p r -k passwd_read
time (for i in $(seq 1 1000); do cat /etc/passwd > /dev/null; done)

# Remove
sudo auditctl -W /etc/passwd -p r -k passwd_read
```

---

## Integrating with fail2ban and alerting

auditd doesn't block — it observes. Pair it with fail2ban, syslog-shipping,
or a custom alerter.

### Alerting on critical keys via `audispd`

`audispd` is the audit event multiplexer. Write a plugin that filters for
keys and sends mail:

```bash
sudo tee /etc/audit/plugins.d/alert-critical.conf > /dev/null <<'EOF'
active = yes
direction = out
path = /usr/local/sbin/audit-alert.sh
type = always
format = string
EOF
```

The script itself:

```bash
sudo tee /usr/local/sbin/audit-alert.sh > /dev/null <<'EOF'
#!/bin/bash
# Reads audit events on stdin, mails a human on critical keys
CRITICAL_KEYS="identity sshd_config sudoers modules"
while read -r line; do
    for k in $CRITICAL_KEYS; do
        if echo "$line" | grep -q "key=\"$k\""; then
            echo "$line" | mail -s "AUDIT alert $(hostname): $k" root
            break
        fi
    done
done
EOF
sudo chmod +x /usr/local/sbin/audit-alert.sh
sudo systemctl restart auditd
```

### Shipping audit logs off the server

Critical. An attacker with root can delete `/var/log/audit/` — you need
the log elsewhere. See `linux-observability` `log-forwarding.md` for
rsyslog/fluent-bit config to ship audit events to a central collector.

---

## Sources

- Book: *Linux System Administration for the 2020s* — intrusion detection
  and compromise response.
- Book: *Ubuntu Server Guide* (Canonical) — security chapters mentioning
  AIDE, auditd, and fail2ban.
- Book: *Mastering Ubuntu* (Atef, 2023) — auditd chapter.
- AIDE upstream: https://aide.github.io/
- Linux audit documentation: https://github.com/linux-audit/audit-documentation
- Man pages: `aide(1)`, `aide.conf(5)`, `auditd(8)`, `auditctl(8)`,
  `auditd.conf(5)`, `audit.rules(7)`, `ausearch(8)`, `aureport(8)`,
  `augenrules(8)`.
