---
name: linux-security-analysis
description: Deep read-only security audit for Debian/Ubuntu and RHEL-family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) servers. Runs 10-layer analysis (kernel, users, network, firewall, web server, databases, filesystem, IDS, backups, packages) and produces a CRITICAL/HIGH/MEDIUM/LOW severity report. The audit must check the mandatory-access-control layer per family — SELinux must be Enforcing on RHEL vs AppArmor profiles loaded on Debian — and use family-specific package and firewall tooling (rpm/dnf + firewalld on RHEL vs dpkg/apt + ufw on Debian). Never modifies the system — use linux-server-hardening to fix findings.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Linux Security Analysis

## Distro support

Two-family skill. The 10-layer audit applies to both families; some layers
inspect different tools. The body uses Debian/Ubuntu; substitute per this matrix.

| Audit layer | Debian/Ubuntu | RHEL family |
|---|---|---|
| Mandatory access control | AppArmor `aa-status` (profiles loaded/enforced) | SELinux `getenforce` must be **Enforcing**; `sestatus` |
| Firewall | `ufw status` | `firewall-cmd --list-all` |
| Installed packages | `dpkg -l`, `apt list --installed` | `rpm -qa`, `dnf list installed` |
| Pending updates | `apt list --upgradable` | `dnf check-update` |
| Auto updates | `unattended-upgrades` configured | `dnf-automatic.timer` active |
| Sudo group membership | `sudo` group | `wheel` group |
| Audit daemon | `auditd` | `auditd` (also surfaces SELinux AVC denials) |

**RHEL-family addition:** a security audit must flag SELinux not Enforcing,
stray `permissive` domains, and unreviewed AVC denials (`ausearch -m AVC`). See
[`../linux-server-hardening/references/selinux-reference.md`](../linux-server-hardening/references/selinux-reference.md)
and [`docs/multi-distro/plan.md`](../docs/multi-distro/plan.md).

## Use when

- Performing a deep, read-only security audit of an Ubuntu/Debian server.
- Building a prioritized findings list before hardening work.
- Re-checking security posture after provisioning or major changes.

## Do not use when

- The task requires making changes; use `linux-server-hardening`.
- The task is limited to one narrower area such as secrets, firewalling, or access control.

## Required inputs

- The target host and its role.
- The desired scope or urgency of the audit.
- Any known concerns that should receive extra scrutiny during the ten-layer review.

## Workflow

1. Confirm the audit is read-only and gather the target server context.
2. Run the fast-path audit if useful, then work through all ten layers.
3. Record findings with severity and concrete evidence.
4. Hand off remediation items to `linux-server-hardening` or the relevant specialist skill.

## Quality standards

- Evidence must be concrete, reproducible, and severity-ranked.
- Keep audit and remediation separate.
- Cover every layer even if an early layer already exposes serious issues.

## Anti-patterns

- Mixing fixes into the audit workflow.
- Reporting vague risk without command output or config evidence.
- Declaring a host secure after checking only one or two layers.

## Outputs

- A CRITICAL/HIGH/MEDIUM/LOW security report with evidence.
- The highest-priority remediation targets.
- A clear handoff to the skill that should fix each class of issue.

## References

- [`references/audit-layers.md`](references/audit-layers.md)
- [`../linux-server-hardening/references/selinux-reference.md`](../linux-server-hardening/references/selinux-reference.md) — SELinux audit checks (RHEL family)

**This skill is self-contained.** The 10 audit layers below work on a stock
Debian/Ubuntu or RHEL-family server using nothing but built-in tools (substitute
family-specific tools per the Distro support matrix). The `sk-audit` script
in the **Optional fast path** section is a convenience wrapper — never
required.

**Read-only.** This skill observes and reports. It never modifies anything.
Use `linux-server-hardening` to fix what this skill finds.

Work through all 10 layers in `references/audit-layers.md`.
For each finding output: `[SEVERITY] Description`
Levels: **CRITICAL** | **HIGH** | **MEDIUM** | **LOW** | **INFO** | **PASS**

---

## Quick Start

```bash
# Optional: run the existing audit script first for a fast PASS/WARN/FAIL overview:
sudo bash ~/.claude/skills/scripts/server-audit.sh

# Then work through the 10 layers for the full deep analysis:
less ~/.claude/skills/linux-security-analysis/references/audit-layers.md
```

## The 10 Layers

See `references/audit-layers.md` for the complete commands for each layer.

| Layer | Focus | Critical findings |
|-------|-------|-------------------|
| 1 | System & kernel | ASLR off, pending CVEs |
| 2 | Users & auth | Extra UID-0, empty passwords, SSH config |
| 3 | Network exposure | Databases on 0.0.0.0 |
| 4 | Firewall | UFW inactive, unexpected open ports |
| 5 | Web server | TLS 1.0/1.1, PHP exposes version, expired certs |
| 6 | Databases | MySQL/Redis/PG on 0.0.0.0, anon users |
| 7 | File system | World-writable web files, cred files not 600 |
| 8 | IDS & monitoring | fail2ban down, AIDE missing |
| 9 | Backup integrity | No recent backup, rclone unreachable |
| 10 | Packages | Security updates pending, unexpected services |

## Severity Guidelines

| Rating | Meaning | Example |
|--------|---------|---------|
| CRITICAL | Exploitable right now | Database on 0.0.0.0, SSH with password auth |
| HIGH | Serious risk | No firewall, expired SSL cert |
| MEDIUM | Should fix soon | AIDE not installed, 20+ pending updates |
| LOW | Best practice gap | X11 forwarding enabled |
| INFO | Informational | Optional tools not installed |
| PASS | Correctly configured | — |

## Report Format

After all 10 layers, output:

```
╔══════════════════════════════════════════════════════╗
║           SECURITY ANALYSIS REPORT                  ║
╠══════════════════════════════════════════════════════╣
║ Host: <hostname>  OS: <distro>  Date: <YYYY-MM-DD>  ║
╚══════════════════════════════════════════════════════╝

[CRITICAL] ...
[HIGH]     ...
[MEDIUM]   ...
[PASS]     ...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 CRITICAL: X  HIGH: X  MEDIUM: X  LOW: X  PASS: X
 Security score: X%
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Recommended: Run linux-server-hardening to fix CRITICAL and HIGH items first.
```

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-security-analysis` installs:

| Task | Fast-path script |
|---|---|
| Full 14-section audit (same as the existing `server-audit.sh`) | `sudo sk-audit` |
| AppArmor profile status + recent denials | `sudo sk-apparmor-status` |

These are optional wrappers. The 10-layer manual procedure above is the
source of truth.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-security-analysis
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-audit | scripts/sk-audit.sh | yes | Read-only 14-section security audit producing PASS/WARN/FAIL report with score. |
| sk-apparmor-status | scripts/sk-apparmor-status.sh | no | List all AppArmor profiles with enforce/complain/disabled status, recent denials from audit.log. |
