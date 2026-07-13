---
name: linux-intrusion-detection
description: Use when operating fail2ban, investigating its bans, or running qualified rkhunter/chkrootkit checks; use linux-auditd-rules or linux-file-integrity for compliance-grade auditing.
license: MIT
metadata:
  portable: true
  compatible_with: [claude-code, codex]
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

<!-- dual-compat-start -->

## Use when

- Managing fail2ban or rootkit scanners (rkhunter/chkrootkit) on Ubuntu/Debian or RHEL-family servers.
- Investigating bans or rootkit-scanner warnings.
- Hardening host monitoring after repeated abuse or suspicious changes.

## Do not use when

- The task is perimeter firewalling or certificates; use `linux-firewall-ssl`.
- The task is a broad read-only security audit; use `linux-security-analysis`.
- The task is system-call auditing (auditd); use `linux-auditd-rules` (15-compliance-and-auditing).
- The task is file-integrity / hash drift (AIDE); use `linux-file-integrity` (15-compliance-and-auditing).

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---|---|
| Host, distro, time window, and signal | Incident owner, alert, or host logs | yes | Inspect current status only; do not claim an incident |
| Known-good baseline and change history | Configuration management or owner | for attribution | Treat integrity warnings as unresolved leads |
| Response authority | Incident commander | for mutation | Preserve evidence; do not ban, tune, or re-baseline |

## Capability Contract

Default investigation uses read/search access and is read-only. Bans, unbans, jail changes, package installation, quarantine, and `rkhunter --propupd` require explicit response authority. Never refresh a baseline merely to silence an unexplained finding.

## Degraded Mode

If logs were rotated, tools are absent, or no trusted baseline exists, report available signals and missing coverage. Mark attribution and compromise status undetermined; a clean partial scan is not a clean host.

## Decision Rules

| Evidence | Action | Failure avoided |
|---|---|---|
| Failures match a jail and policy | Apply authorised ban or tuning | Blocking an address without evidence |
| Warning matches an approved package change | Record benign disposition | Persistent false positive |
| Unexpected change lacks explanation | Preserve evidence and escalate | Baseline laundering |
| SELinux AVC alone | Investigate context | False intrusion declaration |

## Workflow

1. Establish host, clock, log coverage, and authorised boundary; stop when scope is unclear.
2. Preserve the alert and correlated auth, journal, or SELinux records before mutation.
3. Compare the signal with package history and trusted baselines; stop if attribution is unsupported.
4. Classify it as explained, suspicious, confirmed, or unassessed.
5. Apply only authorised reversible containment; restore saved config if validation fails.
6. Re-run the narrow check and record unresolved indicators.

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| Detection evidence pack | Includes jail status, timestamped triggering logs, scanner output, package correlation, authorised diff/action, and post-change status |

## Quality standards

- Changes must improve signal without creating blind spots.
- Preserve evidence when investigating suspicious behavior.
- Keep monitoring rules understandable and reviewable.

## Anti-patterns

- Disabling a noisy jail without understanding why it fired. Fix: test its filter against the triggering logs.
- Re-baselining blindly after a suspicious change. Fix: attribute the change before updating properties.
- Treating detection tooling as root-cause analysis. Fix: correlate the signal with system and application evidence.
- Banning an address from an alert summary alone. Fix: cite triggering records and policy.
- Treating a partial clean scan as a clean host. Fix: state tool and time coverage.
- Updating properties before explanation. Fix: preserve and attribute changes first.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Finding disposition | Incident owner | Links each signal to timestamped evidence and confidence |
| Response record | Operations | Names authorised action and reversal |
| Coverage note | Security owner | States tools, logs, time range, and unassessed areas |

## Worked Example

When `/usr/bin/ssh` changes after an approved OpenSSH update, preserve the warning, match package timestamps and verification, and document the benign cause. Update properties only after approval; an unmatched hash blocks re-baselining.

<!-- dual-compat-end -->

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
