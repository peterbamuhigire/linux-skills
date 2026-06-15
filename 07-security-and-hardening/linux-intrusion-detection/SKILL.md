---
name: linux-intrusion-detection
description: Manage ACTIVE intrusion detection on Debian/Ubuntu and RHEL-family servers (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). fail2ban (check jails, unban IPs, add custom jails, tune bans, read logs) and rootkit scanning with rkhunter and chkrootkit (install, baseline with `--propupd`, scheduled scans, interpreting warnings, reducing false positives) — both run on both families, need EPEL on RHEL/Rocky/Alma, and fail2ban reads journald/`/var/log/secure` via `backend = systemd`. On the RHEL family, SELinux AVC denials are an additional intrusion-detection signal. For the compliance/forensic side — auditd system-call auditing and AIDE file-integrity monitoring — use the dedicated skills linux-auditd-rules and linux-file-integrity in 15-compliance-and-auditing.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Intrusion Detection

## Distro support

Two-family skill. fail2ban and the rootkit scanners (rkhunter, chkrootkit)
run on both families; install and a couple of paths differ, and the RHEL
family adds SELinux AVC denials as an intrusion signal. Body uses
Debian/Ubuntu; substitute per this matrix. **auditd and AIDE moved to
`15-compliance-and-auditing`** — see `linux-auditd-rules` and
`linux-file-integrity`.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| fail2ban install | `apt install fail2ban` | `dnf install fail2ban` (**EPEL** on RHEL/Rocky/Alma; main on Fedora) |
| fail2ban backend | reads `/var/log/auth.log` | reads journald / `/var/log/secure` (use `backend = systemd`) |
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

- Managing fail2ban or rootkit scanners (rkhunter/chkrootkit) on Ubuntu/Debian or RHEL-family servers.
- Investigating bans or rootkit-scanner warnings.
- Hardening host monitoring after repeated abuse or suspicious changes.

## Do not use when

- The task is perimeter firewalling or certificates; use `linux-firewall-ssl`.
- The task is a broad read-only security audit; use `linux-security-analysis`.
- The task is system-call auditing (auditd); use `linux-auditd-rules` (15-compliance-and-auditing).
- The task is file-integrity / hash drift (AIDE); use `linux-file-integrity` (15-compliance-and-auditing).

## Required inputs

- Which subsystem is involved: fail2ban or the rootkit scanners.
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

- Disabling a noisy jail without understanding why it fired.
- Re-baselining a rootkit scanner blindly after a suspicious change.
- Treating intrusion-detection tooling as a substitute for root-cause analysis.

## Outputs

- The status or finding for the selected detection layer.
- The tuning or remediation step taken.
- Verification that the jail, baseline, or audit rule now behaves correctly.

## References

- [`references/fail2ban-jails.md`](references/fail2ban-jails.md)
- [`references/rootkit-scanning.md`](references/rootkit-scanning.md) — rkhunter + chkrootkit on both families (install, baseline, scheduling, false positives, triage)
- [`../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md) — SELinux AVC denials as an IDS signal (RHEL family)
- **auditd (system-call auditing)** moved to [`../../15-compliance-and-auditing/linux-auditd-rules/SKILL.md`](../../15-compliance-and-auditing/linux-auditd-rules/SKILL.md).
- **AIDE (file integrity)** moved to [`../../15-compliance-and-auditing/linux-file-integrity/SKILL.md`](../../15-compliance-and-auditing/linux-file-integrity/SKILL.md).

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

## File integrity (AIDE) and system-call auditing (auditd) — moved

These two **compliance / forensic** layers now live in their own skills under
`15-compliance-and-auditing`:

- **`linux-file-integrity`** — AIDE: build the baseline, run `aide --check`,
  accept changes, schedule, tune `aide.conf`, store the DB off-box. See
  [`../../15-compliance-and-auditing/linux-file-integrity/SKILL.md`](../../15-compliance-and-auditing/linux-file-integrity/SKILL.md).
- **`linux-auditd-rules`** — auditd: `auditctl`, persistent
  `/etc/audit/rules.d/*.rules`, file/syscall watches, key tagging,
  `ausearch`/`aureport`, immutable mode (`-e 2`), rotation. See
  [`../../15-compliance-and-auditing/linux-auditd-rules/SKILL.md`](../../15-compliance-and-auditing/linux-auditd-rules/SKILL.md).

This skill stays focused on **active** intrusion detection: blocking abusive
hosts (fail2ban) and rootkit signature scanning (rkhunter/chkrootkit). The
rootkit scanners below correlate their findings with AIDE drift and auditd
attribution — run those layers from the compliance skills above.

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
| Run rkhunter + chkrootkit with summarised warnings | `sudo sk-rootkit-scan` |
| First-time AIDE install + init + cron (see `linux-file-integrity`) | `sudo sk-file-integrity-init` |
| Run AIDE check with classified results (see `linux-file-integrity`) | `sudo sk-file-integrity-check` |

These are optional wrappers around `fail2ban-client`, `rkhunter`, and
`chkrootkit`. The two `sk-file-integrity-*` rows drive AIDE — documented in
`15-compliance-and-auditing/linux-file-integrity`; their manifest entries are
retained here for backward compatibility with existing installs.

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
