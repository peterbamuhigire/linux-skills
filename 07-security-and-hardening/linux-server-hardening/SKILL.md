---
name: linux-server-hardening
description: Use when an authorised operator wants to remediate verified Linux security findings interactively across SSH, firewall, MAC, services, permissions, and updates; use linux-security-analysis first.
license: MIT
metadata:
  portable: true
  compatible_with: [claude-code, codex]
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Linux Server Hardening

## Distro support

Two-family skill. SSH and kernel/sysctl hardening are largely identical; the
**big difference is mandatory access control** — Debian/Ubuntu use **AppArmor**,
the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) enforces
**SELinux** by default. Full SELinux detail is in
[`references/selinux-reference.md`](references/selinux-reference.md).

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Mandatory access control | **AppArmor** (`aa-status`, `/etc/apparmor.d/`) | **SELinux** (`getenforce`, `sestatus`) — enforcing by default |
| Firewall | `ufw` | `firewalld` |
| Auto security updates | `unattended-upgrades` | `dnf-automatic` |
| Sudo admin group | `sudo` | `wheel` |
| SSH hardening | `/etc/ssh/sshd_config[.d]` | identical |
| sysctl hardening | `/etc/sysctl.d/` | identical |
| Audit daemon | `auditd` | `auditd` (same) |

**Golden rule on RHEL:** never `setenforce 0` to "fix" a problem — diagnose the
denial and set the right context/boolean/port. See
[`references/selinux-reference.md`](references/selinux-reference.md) and
[`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md). In `sk-*` scripts
use the `common.sh` primitives (`pkg_install`, `firewall_allow`, `svc_name`).

<!-- dual-compat-start -->

## Use when

- Applying security fixes after an audit or known hardening gap.
- Locking down SSH, UFW, fail2ban, sysctl, web stack, database, or file-permission posture.
- Converting audit findings into confirmed, staged changes on a live server.

## Do not use when

- You only need a read-only findings report; use `linux-security-analysis`.
- The task is a narrow, non-security operational change better handled by a specialist skill.

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---|---|
| Verified finding and evidence | linux-security-analysis or specialist assessment | yes | Inspect and propose; do not mutate |
| Host role, distro, dependencies, uptime | Inventory and service owner | yes | Stop before changing service behaviour |
| Per-change authority and rollback window | Change owner | for mutation | Return a sequenced hardening plan |
| Recovery access | Console or independent privileged session | for access controls | Do not change SSH, firewall, PAM, or MAC policy |

## Capability Contract

Read/search confirmation precedes every change. Root-level edits, installs, service reloads, firewall changes, and enforcement changes require explicit authority. Preserve an independent recovery path and never broaden scope from one approved finding to an entire baseline.

## Degraded Mode

Without audit evidence, root, recovery access, a maintenance window, or validation tooling, produce the narrowest qualified plan and exact commands for an operator. Leave the finding open; do not claim hardening is complete.

## Decision Rules

| Condition | Action | Failure avoided |
|---|---|---|
| Change can break remote access | Test syntax and preserve a second session/console | Lockout |
| SELinux/AppArmor denial is unexplained | Diagnose labels/profile before policy exception | Disabling mandatory access control |
| Several high-risk changes are requested | Apply and validate one control at a time | Untraceable outage |
| Verification contradicts expected result | Roll back and stop the cohort | Compounding a failed change |

## Workflow

1. Reproduce the finding, identify distro/role dependencies, and confirm scope.
2. Define success, rollback, recovery access, and a syntax/config test; stop if any is missing.
3. Back up the affected config and preview the smallest change.
4. Apply one authorised control and validate access, syntax, service health, and application behaviour.
5. Roll back immediately on failed validation; preserve output and stop related changes.
6. Re-run the original audit check and record closure or residual risk.

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| Hardening evidence pack | Includes finding, approval, backup/diff, syntax checks, commands, service/access validation, rollback if used, and repeated audit check |

## Quality standards

- Every hardening step must be deliberate, reversible, and verified.
- Preserve operator access while tightening controls.
- Close findings with evidence, not intention.

## Anti-patterns

- Hardening blind. Fix: reproduce a verified finding or define a precise target.
- Bundling high-risk changes. Fix: validate and checkpoint each control.
- Calling a control fixed before re-checking. Fix: repeat the original audit test.
- Disabling SELinux or AppArmor to clear a denial. Fix: fix labels, context, or narrow policy.
- Editing SSH without recovery access. Fix: preserve a second session or console and run `sshd -t`.
- Assuming rollback exists. Fix: create and test the config backup and restore command.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Hardening change record | Change owner | Links finding, approval, exact diff, and rollback |
| Validation evidence | Service owner | Proves access, syntax, service, and original check |
| Residual-risk register | Risk owner | Names deferred or failed controls and next action |

## Worked Example

For password SSH still enabled on Ubuntu, first verify key login in a second session, back up `sshd_config`, change only `PasswordAuthentication`, run `sshd -t`, reload SSH, and prove a new key session works before closing the old one. Restore the backup if validation fails.

<!-- dual-compat-end -->

## References

- [`references/hardening-checklist.md`](references/hardening-checklist.md)
- [`references/sysctl-reference.md`](references/sysctl-reference.md)
- [`references/selinux-reference.md`](references/selinux-reference.md)
- [`../../01-provisioning-and-bootstrap/linux-package-management/SKILL.md`](../../01-provisioning-and-bootstrap/linux-package-management/SKILL.md) — package hygiene, Flatpak/snap, and workstation AppImage runtime support.

**This skill is self-contained.** Every hardening step below uses standard
tools on both Debian/Ubuntu and the RHEL family (Fedora, RHEL, CentOS Stream,
Rocky, Alma, Oracle); see the **Distro support** table above for the
family-specific equivalents. The `sk-*` scripts in the **Optional fast path**
section are convenience wrappers — never required.

Applies security fixes interactively. Runs the audit first — never applies
a change without your confirmation.

**For a full picture first:** run `linux-security-analysis` before hardening.

**Desktop/workstation exception:** AppImage runtime packages such as `fuse3`,
`desktop-file-utils`, and app-specific media libraries (`mpv-libs` on Fedora)
belong to workstation package setup, not production server hardening. Keep them
off headless servers unless a real desktop app requirement exists; use
`linux-package-management` when such a requirement is present.

---

## Step 1: Run The Audit

```bash
sudo bash ~/.claude/skills/scripts/server-audit.sh
```

Fix FAIL items first, then WARN. Use `references/hardening-checklist.md`
for the complete commands for each area.

---

## Hardening Areas (In Priority Order)

### 1. SSH
- Disable password auth, disable root login, set MaxAuthTries 3
- **WARNING:** Keep existing SSH session open. Test login in a second terminal
  before closing the first session.
- Config: `/etc/ssh/sshd_config.d/99-hardening.conf`
- Script: `sudo sk-harden-ssh` (tests before reload, backs up existing config)

### 2. Firewall (UFW)
- Default deny incoming, allow 22/80/443 only
- `sudo ufw status verbose` to check current state
- Script: `sudo sk-ufw-reset` (interactive profile picker)

### 3. Kernel (sysctl)
- Network stack hardening + ASLR + kernel pointer restriction
- Config: `/etc/sysctl.d/99-linux-skills.conf`
- Script: `sudo sk-harden-sysctl`

### 4. Nginx
- `server_tokens off` in nginx.conf
- Security headers on all vhosts (or global security.conf)
- Dotfile blocking snippet included in all vhosts

### 5. PHP-FPM
- `expose_php = Off`, `display_errors = Off`, `allow_url_include = Off`
- Session cookie security settings
- `disable_functions` for dangerous functions
- Config: `/etc/php/8.3/fpm/php.ini`
- Script: `sudo sk-harden-php`

### 6. MySQL
- `bind-address = 127.0.0.1` (never expose to network)
- Run `mysql_secure_installation`
- Application users: least-privilege only

### 7. Redis
- Bound to 127.0.0.1, password set, dangerous commands renamed

### 8. File Permissions
- `/etc/shadow` → 640, credential files → 600
- No world-writable files in `/var/www`
- SSH keys → 600

### 9. Automatic Updates
- `unattended-upgrades` installed and enabled

---

## Verify After Hardening

```bash
sudo bash ~/.claude/skills/scripts/server-audit.sh
# All previous FAIL items should now be PASS
```

Full configs and commands for each area: `references/hardening-checklist.md`
Reference guide: `~/.claude/skills/notes/server-security.md`

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-server-hardening` installs:

| Task | Fast-path script |
|---|---|
| Apply SSH hardening (backs up first, tests before reload) | `sudo sk-harden-ssh` |
| Apply sysctl kernel hardening | `sudo sk-harden-sysctl` |
| Apply PHP hardening | `sudo sk-harden-php` |
| Triage SELinux denials, build reviewed policy module (RHEL family) | `sudo sk-selinux-denials` |

These wrap the manual steps in `references/hardening-checklist.md`.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-server-hardening
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-harden-ssh | scripts/sk-harden-ssh.sh | no | Apply SSH hardening: disable root, password auth off, `MaxAuthTries=3`, banner; backs up original first. |
| sk-harden-sysctl | scripts/sk-harden-sysctl.sh | no | Write `/etc/sysctl.d/99-linux-skills.conf` with ASLR, SYN cookies, rp_filter, icmp ignore_bogus. |
| sk-harden-php | scripts/sk-harden-php.sh | no | Apply PHP hardening: `expose_php=off`, `display_errors=off`, `disable_functions`, session flags. |
| sk-selinux-denials | scripts/sk-selinux-denials.sh | no | RHEL family only. Summarize recent AVC denials (`ausearch`/`aureport --avc`), explain with `audit2why`, then — only after you confirm — build a reviewed local policy module (`audit2allow -M` + `semodule -i`). Never disables SELinux. See `references/selinux-reference.md`. |
