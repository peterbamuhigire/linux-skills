# auditd: rules, analysis, and immutability

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This file is the deep reference for **auditd**, the Linux kernel audit
daemon. auditd answers *who did what, and when?* — it hooks the kernel audit
subsystem and logs syscalls and file accesses matching rules you define
(file writes, process execution, privilege escalation). It is the
attribution layer of compliance auditing; pair it with file-integrity drift
detection (`linux-file-integrity`, AIDE) and benchmark scanning
(`linux-benchmark-scanning`, OpenSCAP/Lynis).

auditd is **identical across both families** — same `auditctl` syntax, same
`/etc/audit/rules.d/`, same `ausearch`/`aureport`. The only differences are
the install package and, on the RHEL family, ready-made compliance rulesets
shipped by `scap-security-guide`.

## Table of contents

- [Install and enable](#install-and-enable)
- [Daemon config essentials](#daemon-config-essentials)
- [Writing rules in /etc/audit/rules.d/](#writing-rules-in-etcauditrulesd)
- [auditctl: runtime control and options](#auditctl-runtime-control-and-options)
- [The rule catalogue](#the-rule-catalogue)
- [Immutable mode (-e 2)](#immutable-mode--e-2)
- [Pre-configured compliance rulesets (PCI-DSS, CIS, STIG)](#pre-configured-compliance-rulesets-pci-dss-cis-stig)
- [Reading the log: ausearch](#reading-the-log-ausearch)
- [Reading the log: aureport](#reading-the-log-aureport)
- [Rotation and performance](#rotation-and-performance)
- [Alerting on critical keys](#alerting-on-critical-keys)
- [Shipping audit logs off the server](#shipping-audit-logs-off-the-server)
- [Sources](#sources)

---

## Install and enable

```bash
# Debian/Ubuntu
sudo apt install auditd audispd-plugins

# RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) — usually preinstalled
sudo dnf install audit

sudo systemctl enable --now auditd
sudo systemctl status auditd --no-pager
```

Key paths (same on both families):

- `/etc/audit/auditd.conf` — daemon config (log location, rotation, buffer).
- `/etc/audit/rules.d/*.rules` — drop-in rule files; combined into
  `/etc/audit/audit.rules` at daemon start via `augenrules`.
- `/var/log/audit/audit.log` — the log (mode 600, root-only).

---

## Daemon config essentials

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

`halt` sounds scary but is the correct posture for a high-security host: if
auditd can't write its log, something is actively going wrong and the server
should not continue processing silently. For development servers, change to
`suspend` or `syslog` during setup, then `halt` once stable.

---

## Writing rules in /etc/audit/rules.d/

### File-watch rules

```
-w <path> -p <perms> -k <key>
```

- `<path>` — file or directory to watch.
- `<perms>` — any combination of `r` (read), `w` (write), `x` (execute),
  `a` (attribute change).
- `<key>` — a short tag you'll use in `ausearch`/`aureport`.

### Syscall rules

```
-a always,exit -F arch=b64 -S <syscall> -k <key>
```

- `always,exit` — audit on every exit from the syscall.
- `arch=b64` — 64-bit. Duplicate with `arch=b32` to also catch 32-bit binaries.
- `-S <syscall>` — the syscall to trigger on (`execve`, `openat`, `unlink`,
  `chmod`, etc.). Multiple `-S` may be combined in one rule.
- `-F <field>=<value>` — extra filters (`euid=0`, `auid>=1000`,
  `path=/usr/bin/sudo`).
- `-k <key>` — tag.

Compile and load drop-ins:

```bash
sudo augenrules --load          # assemble rules.d/ → audit.rules and load
sudo auditctl -l | head -30     # confirm
```

---

## auditctl: runtime control and options

`auditctl` configures the kernel audit system live, without restarting
auditd — ideal for testing a rule before persisting it.

```bash
# General syntax
auditctl [options] [rules]

# Add a file watch
sudo auditctl -w /etc/passwd -p wa -k passwd_changes

# Add a syscall rule (audit chmod-family calls)
sudo auditctl -a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -k perm_changes

# Audit a specific user's command execution
sudo auditctl -a always,exit -F arch=b64 -F auid=$(id -u user1) -S execve -k user1_exec

# List all loaded rules
sudo auditctl -l

# Delete all rules
sudo auditctl -D

# Enable / disable / lock auditing
sudo auditctl -e 1              # enable
sudo auditctl -e 0              # disable
sudo auditctl -e 2              # lock immutable until reboot

# Status (enabled flag, failure mode, pid, rate_limit, backlog_limit, LOST)
sudo auditctl -s

# Rate and backlog tuning
sudo auditctl -r 100            # max 100 audit messages/second
sudo auditctl -b 8192           # backlog queue size (raise if events are lost)
```

`auditctl -s` is the single most useful health command: check `enabled`,
`failure`, and especially `lost` (a nonzero `lost` means events are being
dropped — raise `-b` or narrow rules).

---

## The rule catalogue

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
-w /etc/apache2      -p wa -k apache_config     # /etc/httpd on RHEL family
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
-w /etc/netplan    -p wa -k network_config     # /etc/NetworkManager on RHEL family
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

## Immutable mode (-e 2)

End the rule file with `-e 2` to lock the rule set until reboot:

```
-e 2
```

Once `-e 2` is active, rule changes require a reboot. This is correct for
production: an attacker with root can't silently disable auditing during an
incident. During setup, use `-e 0` or omit, and flip to `-e 2` after the
rules are proven stable. Confirm with `auditctl -s` (`enabled 2` = immutable).

---

## Pre-configured compliance rulesets (PCI-DSS, CIS, STIG)

On the RHEL family the `scap-security-guide` package ships ready-made audit
rulesets aligned with certification standards — there's no need to
hand-write them:

```bash
sudo dnf install scap-security-guide

# Pre-built rules live here:
ls /usr/share/audit/sample-rules/

# Apply, e.g., the PCI-DSS ruleset:
sudo cp /usr/share/audit/sample-rules/30-pci-dss-v31.rules /etc/audit/rules.d/
sudo augenrules --load
sudo auditctl -l                 # verify loaded
```

You can also drive these profiles end-to-end with OpenSCAP — see
[`../../linux-benchmark-scanning/references/openscap-reference.md`](../../linux-benchmark-scanning/references/openscap-reference.md).
Customise a copied ruleset only in ways that don't conflict with the
standard's requirements.

On Debian/Ubuntu there is no equivalent packaged sample set; start from the
catalogue above or the upstream `audit` project samples.

---

## Reading the log: ausearch

The log is binary-ish. Use `ausearch` and `aureport`, not `less`.

```bash
# Everything tagged sudoers (-i interprets uid/gid into names)
sudo ausearch -k sudoers -i

# Everything tagged identity in the last hour
sudo ausearch -k identity --start recent -i

# Specific date range
sudo ausearch --start "04/10/2026 14:00:00" --end "04/10/2026 14:30:00" -i

# By file
sudo ausearch -f /etc/passwd -i

# By original (login) user ID — survives su/sudo
sudo ausearch -ua 1000 -i

# By executable
sudo ausearch -x /usr/bin/sudo -i

# SELinux AVC denials (RHEL family)
sudo ausearch -m AVC -ts recent
sudo ausearch -m AVC -c sshd
```

### Example investigation: who edited /etc/passwd?

```bash
sudo ausearch -f /etc/passwd -i | less
```

Look for:

- `type=SYSCALL` events.
- `exe="/usr/bin/nano"` or similar — the binary that touched the file.
- `comm="nano"` — the command name.
- `auid=1000` — who was logged in (the audit UID survives `su` and `sudo`).
- `success=yes` — did the syscall succeed?

Correlate the timestamp with the SSH login in `/var/log/auth.log`
(Debian/Ubuntu) or `/var/log/secure` (RHEL family).

---

## Reading the log: aureport

```bash
# Overall summary
sudo aureport --summary

# Failed / successful logins
sudo aureport -au --failed
sudo aureport -au --success

# Executed commands (requires execve syscall rules)
sudo aureport -x --summary

# Files accessed (requires file rules)
sudo aureport -f --summary

# Events by key
sudo aureport -k --summary

# SELinux AVC summary (RHEL family)
sudo aureport --avc
```

Automate a daily compliance summary via cron:

```bash
echo "0 0 * * * root /usr/sbin/aureport --summary > /var/log/audit/daily-summary.txt" \
    | sudo tee /etc/cron.d/aureport-daily
```

---

## Rotation and performance

### Rotation

Handled by `auditd` itself via `/etc/audit/auditd.conf`:

- `max_log_file = 100` — rotate at 100 MB.
- `num_logs = 10` — keep 10 rotated copies.
- `max_log_file_action = ROTATE`.

Check current log size:

```bash
sudo ls -lh /var/log/audit/
sudo du -sh /var/log/audit/
```

### Performance impact

Watching directories with many small files (e.g. `/var/www/html` for a
WordPress site with 10k files) is expensive, and read-perm (`-p r`) watches
on hot files flood the log. If CPU or I/O rises after adding a rule, narrow
the path or drop the rule.

```bash
sudo auditctl -s             # status, losses, and backlog
```

Watch `lost` — if nonzero, auditd is dropping events. Raise the buffer
(`-b 16384`) or narrow the rules.

### Testing the overhead of a rule

```bash
# Baseline
time (for i in $(seq 1 1000); do cat /etc/passwd > /dev/null; done)

# Add a read watch
sudo auditctl -w /etc/passwd -p r -k passwd_read
time (for i in $(seq 1 1000); do cat /etc/passwd > /dev/null; done)

# Remove it
sudo auditctl -W /etc/passwd -p r -k passwd_read
```

---

## Alerting on critical keys

auditd doesn't block — it observes. Pair it with alerting via `audispd`, the
audit event multiplexer.

```bash
sudo tee /etc/audit/plugins.d/alert-critical.conf > /dev/null <<'EOF'
active = yes
direction = out
path = /usr/local/sbin/audit-alert.sh
type = always
format = string
EOF
```

The script:

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

---

## Shipping audit logs off the server

Critical for compliance and forensics: an attacker with root can delete
`/var/log/audit/`, so you need the log elsewhere. Forward with rsyslog to a
central collector:

```bash
sudo tee /etc/rsyslog.d/audit.conf > /dev/null <<'EOF'
# Forward audit log to a central collector
*.* @@logserver.example.com:514
EOF
sudo systemctl restart rsyslog
```

See `linux-observability` `log-forwarding.md` for rsyslog/fluent-bit config
to ship audit events to a central collector or SIEM.

---

## Sources

- Book: *Red Hat Enterprise Linux 9 for SysAdmins* (Jerome Gotangco) —
  Recipes #96–98: configuring auditd, defining rules with `auditctl`,
  `augenrules --load`, `ausearch`/`aureport`, and pre-configured certification
  rulesets (PCI-DSS, CIS, STIG) via `scap-security-guide`.
- RHCSA-level auditd basics: install, enable, `/etc/audit/rules.d/`,
  immutable mode.
- Linux audit documentation: https://github.com/linux-audit/audit-documentation
- Man pages: `auditd(8)`, `auditctl(8)`, `auditd.conf(5)`, `audit.rules(7)`,
  `ausearch(8)`, `aureport(8)`, `augenrules(8)`.
