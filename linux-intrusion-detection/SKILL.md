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

## fail2ban

```bash
# Quick status report:
sudo sk-fail2ban-status

# Manual commands:
sudo fail2ban-client status                      # all jails + count
sudo fail2ban-client status <jail>               # specific jail (bans, IPs)
sudo tail -f /var/log/fail2ban.log               # live ban activity

# Unban an IP
sudo fail2ban-client set <jail> unbanip <ip>

# Reload after config change
sudo systemctl reload fail2ban
```

Full jail configuration templates: `references/fail2ban-jails.md`

---

## AIDE (File Integrity Monitoring)

```bash
# First-time initialization (installs, runs aideinit, sets up cron):
sudo sk-file-integrity-init

# Run a check (summarizes + classifies changes, alerts on binary drift):
sudo sk-file-integrity-check
```

Manual commands if needed:

```bash
sudo apt install aide
sudo aideinit
sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
sudo aide --check
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
