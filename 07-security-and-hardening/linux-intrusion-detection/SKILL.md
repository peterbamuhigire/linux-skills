---
name: linux-intrusion-detection
description: Manage intrusion detection on Debian/Ubuntu and RHEL-family servers (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). fail2ban (check jails, unban IPs, add custom jails, tune bans, read logs), AIDE file integrity monitoring (install, initialise, run checks, schedule daily), auditd system call auditing (install, watch files, read audit log), and rootkit scanning with rkhunter and chkrootkit (install, baseline with `--propupd`, scheduled scans, interpreting warnings, reducing false positives) all run on both families — fail2ban and the rootkit scanners need EPEL on RHEL/Rocky/Alma, and fail2ban reads journald/`/var/log/secure` via `backend = systemd`. On the RHEL family, SELinux AVC denials are an additional intrusion-detection signal.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Intrusion Detection

## Distro support

Two-family skill. fail2ban, AIDE, auditd, and the rootkit scanners
(rkhunter, chkrootkit) run on both families; install and a couple of paths
differ, and the RHEL family adds SELinux AVC denials as an intrusion signal.
Body uses Debian/Ubuntu; substitute per this matrix.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| fail2ban install | `apt install fail2ban` | `dnf install fail2ban` (**EPEL** on RHEL/Rocky/Alma; main on Fedora) |
| fail2ban backend | reads `/var/log/auth.log` | reads journald / `/var/log/secure` (use `backend = systemd`) |
| AIDE | `apt install aide` | `dnf install aide` |
| auditd | `auditd` | `auditd` (same) |
| rkhunter / chkrootkit | `apt install rkhunter chkrootkit` | `dnf install rkhunter chkrootkit` (**EPEL** on RHEL/Rocky/Alma/Oracle; main on Fedora) |
| Rootkit scan auto-run | `/etc/cron.daily/rkhunter` + `/etc/default/rkhunter` | no packaged wrapper — use systemd timer / cron |
| MAC denials as IDS signal | AppArmor (`journalctl -k \| grep apparmor`) | **SELinux AVC** (`ausearch -m AVC`, `aureport --avc`) |
| Web/auth log paths | `/var/log/auth.log` | `/var/log/secure` |

**RHEL-family note:** fail2ban on RHEL usually needs `backend = systemd` (and
the right `logpath`/journal match) because `/var/log/auth.log` does not exist —
auth events go to `/var/log/secure` and journald. Treat new SELinux AVC denials
as a triage signal. See
[`../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md)
and [`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

## Use when

- Managing fail2ban, AIDE, auditd, or rootkit scanners (rkhunter/chkrootkit) on Ubuntu/Debian or RHEL-family servers.
- Investigating bans, file-integrity alerts, syscall audit trails, or rootkit-scanner warnings.
- Hardening host monitoring after repeated abuse or suspicious changes.

## Do not use when

- The task is perimeter firewalling or certificates; use `linux-firewall-ssl`.
- The task is a broad read-only security audit; use `linux-security-analysis`.

## Required inputs

- Which subsystem is involved: fail2ban, AIDE, or auditd.
- The host, jail, file path, or event pattern under investigation.
- Whether the task is inspection, tuning, or first-time setup.

## Workflow

1. Confirm which detection layer matches the symptom.
2. Inspect current status, logs, and configured watches or jails.
3. Apply the minimum tuning or recovery change needed.
4. Re-run the relevant check to prove the monitoring layer behaves as expected.

## Quality standards

- Changes must improve signal without creating blind spots.
- Preserve evidence when investigating suspicious behavior.
- Keep monitoring rules understandable and reviewable.

## Anti-patterns

- Disabling a noisy jail or audit rule without understanding why it fired.
- Rebuilding AIDE baselines blindly after suspicious change.
- Treating intrusion-detection tooling as a substitute for root-cause analysis.

## Outputs

- The status or finding for the selected detection layer.
- The tuning or remediation step taken.
- Verification that the jail, baseline, or audit rule now behaves correctly.

## References

- [`references/fail2ban-jails.md`](references/fail2ban-jails.md)
- [`references/aide-and-auditd.md`](references/aide-and-auditd.md)
- [`references/rootkit-scanning.md`](references/rootkit-scanning.md) — rkhunter + chkrootkit on both families (install, baseline, scheduling, false positives, triage)
- [`../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md) — SELinux AVC denials as an IDS signal (RHEL family)

**This skill is self-contained.** Every command below is a standard
Debian/Ubuntu or RHEL-family tool (see **Distro support** for the install and
path substitutions). The `sk-*` scripts in the **Optional fast path** section
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

## Rootkit scanning (rkhunter + chkrootkit)

Signature/heuristic layer on top of AIDE (drift) and auditd (attribution).
rkhunter keeps a file-property baseline and checks for known rootkit
fingerprints; chkrootkit is a baseline-free signature scanner. Run **both** —
they catch different things, and agreement raises confidence.

```bash
# Install (RHEL family: enable EPEL first on RHEL/Rocky/Alma/Oracle)
sudo apt install rkhunter chkrootkit        # dnf install rkhunter chkrootkit

# Refresh definitions, then baseline file properties on a KNOWN-CLEAN host
sudo rkhunter --update
sudo rkhunter --propupd                     # like aideinit — clean host only!

# Scan
sudo rkhunter --check --sk --rwo            # --sk = no pause, --rwo = warnings only
sudo chkrootkit -q                          # -q = show only INFECTED/suspicious

# Re-baseline after a CONFIRMED-legitimate change (e.g. package upgrade)
sudo rkhunter --propupd
```

**Warnings are "verify", never "confirmed rootkit".** Most are false
positives (package updates, hidden `.git`, DHCP promiscuous mode). Confirm a
changed binary against the package (`dpkg -V` / `rpm -V`), whitelist the
*specific* false positive in `/etc/rkhunter.conf.local` (set `PKGMGR=DPKG` or
`RPM`), and never disable a whole test to silence one line. Correlate flagged
paths with AIDE and auditd before declaring an incident.

Install, scheduling (systemd timer / cron), false-positive tuning, and the
full triage flow: `references/rootkit-scanning.md`

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-intrusion-detection` installs:

| Task | Fast-path script |
|---|---|
| fail2ban status report with recent blocks | `sudo sk-fail2ban-status` |
| First-time AIDE install + init + cron | `sudo sk-file-integrity-init` |
| Run AIDE check with classified results | `sudo sk-file-integrity-check` |
| Run rkhunter + chkrootkit with summarised warnings | `sudo sk-rootkit-scan` |

These are optional wrappers around `fail2ban-client`, `aide`, `auditd`,
`rkhunter`, and `chkrootkit`.

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
| sk-rootkit-scan | scripts/sk-rootkit-scan.sh | no | Run rkhunter + chkrootkit, summarize warning counts, gate `--propupd` re-baseline, point triage at AIDE/auditd. |
