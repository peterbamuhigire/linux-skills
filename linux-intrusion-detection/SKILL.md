---
name: linux-intrusion-detection
description: Manage intrusion detection on Ubuntu/Debian servers. fail2ban (check jails, unban IPs, add custom jails, tune bans, read logs). AIDE file integrity monitoring (install, initialise, run checks, schedule daily). auditd system call auditing (install, watch files, read audit log).
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Intrusion Detection

**This skill is self-contained.** Every command below is a standard
Ubuntu/Debian tool. The `sk-*` scripts in the **Optional fast path** section
are convenience wrappers — never required.

## fail2ban

```bash
sudo fail2ban-client status                      # all jails + count
sudo fail2ban-client status <jail>               # specific jail (bans, IPs)
sudo tail -f /var/log/fail2ban.log               # live ban activity

# Unban an IP
sudo fail2ban-client set <jail> unbanip <ip>

# Reload after config change
sudo systemctl reload fail2ban
sudo fail2ban-client status                      # verify jails loaded
```

Full jail configuration templates: `references/fail2ban-jails.md`

---

## AIDE (File Integrity Monitoring)

```bash
# Install
sudo apt install aide

# Initialise (first time — takes a few minutes)
sudo aideinit
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Run integrity check
sudo aide --check
# No output = no changes. Any output = files changed since last init.

# Update DB after intentional changes (e.g. after a deployment)
sudo aideinit
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
```

### Schedule Daily AIDE Check

```bash
sudo nano /etc/cron.daily/aide-check
```
```bash
#!/bin/bash
aide --check | mail -s "AIDE Report $(hostname) $(date +%Y-%m-%d)" root
```
```bash
sudo chmod +x /etc/cron.daily/aide-check
```

---

## auditd (System Call Auditing)

```bash
sudo apt install auditd
sudo systemctl enable auditd && sudo systemctl start auditd

# Watch critical files:
sudo auditctl -w /etc/passwd -p rwxa -k passwd-changes
sudo auditctl -w /etc/shadow -p rwxa -k shadow-changes
sudo auditctl -w /etc/ssh/sshd_config -p rwxa -k ssh-config
sudo auditctl -w /var/www -p w -k webroot-writes

# Make rules permanent:
sudo nano /etc/audit/rules.d/hardening.rules
# Add the -w rules above

# Search audit log:
sudo ausearch -k passwd-changes
sudo ausearch -f /etc/passwd
sudo ausearch --start today
sudo aureport --summary
```

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-intrusion-detection` installs:

| Task | Fast-path script |
|---|---|
| fail2ban status report with recent blocks | `sudo sk-fail2ban-status` |
| First-time AIDE install + init + cron | `sudo sk-file-integrity-init` |
| Run AIDE check with classified results | `sudo sk-file-integrity-check` |

These are optional wrappers around `fail2ban-client`, `aide`, and `auditd`.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-intrusion-detection
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-fail2ban-status | scripts/sk-fail2ban-status.sh | yes | Jails, active bans, total bans by jail, recent blocks with geo hints. |
| sk-file-integrity-init | scripts/sk-file-integrity-init.sh | no | Initialize AIDE database, verify baseline, install nightly cron. |
| sk-file-integrity-check | scripts/sk-file-integrity-check.sh | no | Run AIDE check, summarize changes, classify (config/log/binary), alert on binary drift. |
