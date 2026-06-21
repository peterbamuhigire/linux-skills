---
name: linux-server-provisioning
description: Set up a fresh server from scratch for production web hosting across two families — Debian/Ubuntu and RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). The provisioning sequence is the same; tools differ by package manager (apt/dnf), firewall (ufw/firewalld), MAC (AppArmor/SELinux), admin group (sudo/wheel), auto-updates (unattended-upgrades/dnf-automatic), and install automation (autoinstall/Kickstart). Interactive step-by-step. Covers hostname, timezone, admin user, SSH hardening, firewall, full stack installation (Nginx, Apache port 8080, PHP-FPM, MySQL 8, PostgreSQL, Redis, Node.js, fail2ban, certbot, rclone, msmtp), Nginx snippet setup, and post-install security verification.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Server Provisioning

## Distro support

Two-family skill. The provisioning *sequence* is the same; the tools at each
step differ. Body uses Debian/Ubuntu; substitute per this matrix.

| Provisioning step | Debian/Ubuntu | RHEL family |
|---|---|---|
| Package manager | `apt` | `dnf` |
| Update + base packages | `apt update && apt install …` | `dnf install …` (`ensure_epel` for extras on RHEL/Rocky/Alma) |
| Admin user group | `usermod -aG sudo <u>` | `usermod -aG wheel <u>` |
| Firewall | `ufw` | `firewalld` |
| Auto security updates | `unattended-upgrades` | `dnf-automatic` |
| Workstation AppImage support | `fuse3 desktop-file-utils`; add `libfuse2`/`libfuse2t64` for legacy AppImages | `fuse3 desktop-file-utils`; add app-specific libs such as `mpv-libs` when needed |
| Mandatory access control | AppArmor (already on) | **SELinux enforcing** (already on) |
| Time sync | `systemd-timesyncd` | `chronyd` |
| Install automation | autoinstall (subiquity) | **Kickstart** (Anaconda) |
| Regenerate GRUB2 | `update-grub` → `/boot/grub/grub.cfg` | `grub2-mkconfig -o /boot/grub2/grub.cfg` (UEFI: `/boot/efi/EFI/<distro>/`) |
| Set/list default kernel | `grub-set-default` + `update-grub` | `grubby --set-default` / `grub2-set-default`; `grubby --default-kernel` |
| Edit kernel boot args | edit `GRUB_CMDLINE_LINUX` + regenerate | `grubby --update-kernel ALL --args/--remove-args` |

See [`../../01-provisioning-and-bootstrap/linux-cloud-init/references/kickstart-reference.md`](../../01-provisioning-and-bootstrap/linux-cloud-init/references/kickstart-reference.md)
for automated installs and
[`../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md)
for SELinux. Workstation-only AppImage package baselines are owned by
[`linux-package-management`](../linux-package-management/SKILL.md); add them
only when the target host is a desktop/workstation, not a headless production
server. In `sk-*` scripts use the `common.sh` primitives (`pkg_install`,
`ensure_epel`, `firewall_allow`, `svc_name`) instead of hardcoding. Plan:
[`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

## Use when

- Building a fresh Ubuntu/Debian server for production use.
- Standardizing a new host before application deployment.
- Performing the baseline setup that later specialist skills depend on.

## Do not use when

- The host is already provisioned and you only need a narrower change.
- The setup should be fully declarative from image boot; use `linux-cloud-init`.

## Required inputs

- Hostname, timezone, and target stack choices.
- The admin access model and any required packages or services.
- Any environment-specific requirements for backups, SSL, or deployment tooling.

## Workflow

1. Collect the required server identity and stack decisions up front.
2. Work through the numbered provisioning sections in order.
3. Validate access, package installs, services, and baseline security after each major stage.
4. Finish with post-install verification before handing the host to deployment or operations work.

## Quality standards

- Provisioning should create a predictable baseline, not an improvised snowflake.
- Security and access validation are part of provisioning, not follow-up chores.
- Leave the server ready for repeatable operational workflows.

## Anti-patterns

- Skipping foundational steps such as SSH hardening, firewalling, or update policy.
- Mixing ad-hoc application deployment into the base build before the platform is stable.
- Ending the workflow before post-install verification passes.

## Outputs

- A provisioned server baseline.
- The chosen host identity and stack decisions.
- A verification checklist proving the build is operational and secure enough for next steps.

## References

- [`references/provisioning-steps.md`](references/provisioning-steps.md)
- [`references/post-install-verification.md`](references/post-install-verification.md)
- [`references/grub2-and-kernel-rollback.md`](references/grub2-and-kernel-rollback.md) — GRUB2 config model per family, default-kernel and boot-parameter management, kernel lifecycle, and rolling back to a known-good kernel after a panic
- [`../../01-provisioning-and-bootstrap/linux-cloud-init/references/kickstart-reference.md`](../../01-provisioning-and-bootstrap/linux-cloud-init/references/kickstart-reference.md) — Kickstart automated install (RHEL family)
- [`../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md) — SELinux on a fresh RHEL server
- [`../../09-troubleshooting-and-recovery/linux-disaster-recovery/SKILL.md`](../../09-troubleshooting-and-recovery/linux-disaster-recovery/SKILL.md) — GRUB *regeneration after corruption* and initramfs/filesystem repair from a rescue environment (use when GRUB itself is broken, not just the kernel)

**This skill is self-contained.** The 11-section manual procedure below uses
only standard tools — Debian/Ubuntu by default, with RHEL-family equivalents
per the **Distro support** matrix above. The `sk-provision-fresh` script in the
**Optional fast path** section is a convenience wrapper — never required.

Sets up a fresh server. Ask first:
1. **Hostname?**
2. **Timezone?** (default: Africa/Nairobi)
3. **Which stack?** (confirm: Nginx + Apache + PHP8.3 + MySQL + PostgreSQL + Redis)

Work through sections in order. Full commands: `references/provisioning-steps.md`

---

## Section Overview

| # | Section | Est. time |
|---|---------|-----------|
| 1 | System update + hostname + timezone | 5 min |
| 2 | Admin user + sudo | 2 min |
| 3 | SSH hardening | 5 min |
| 4 | UFW firewall | 2 min |
| 5 | Automatic security updates | 2 min |
| 6 | Web stack (Nginx, Apache, PHP-FPM) | 10 min |
| 7 | Databases (MySQL, PostgreSQL, Redis) | 10 min |
| 8 | Supporting tools (fail2ban, certbot, rclone, msmtp, Node.js) | 10 min |
| 9 | Nginx snippets + catch-all config | 10 min |
| 10 | Clone linux-skills + install sk-* scripts | 5 min |
| 11 | Post-install security check | 5 min |

---

## Critical Steps (Do Not Skip)

```bash
# After SSH hardening — ALWAYS test in a second terminal before closing first:
ssh administrator@<server-ip>

# After Apache port change — verify it's on 8080 not 80:
ss -tlnp | grep apache

# After MySQL install — bind to localhost:
grep bind-address /etc/mysql/mysql.conf.d/mysqld.cnf

# Final check:
sudo bash ~/.claude/skills/scripts/server-audit.sh
```

---

## Quick Reference

```bash
# Test Nginx config
sudo nginx -t && sudo systemctl reload nginx

# All services should be active after provisioning:
for s in nginx apache2 mysql postgresql php8.3-fpm redis fail2ban; do
    printf "%-20s %s\n" $s "$(systemctl is-active $s)"
done

# Verify firewall
sudo ufw status verbose
```

Full step-by-step installation commands: `references/provisioning-steps.md`
Next step after provisioning: `linux-server-hardening`

---

## Boot / bootloader management

Part of standing up a host is owning its boot path — GRUB2 config, which kernel
is the default, boot parameters, and (critically) being able to **roll back to a
known-good kernel after a panic**. This lives here because it is provisioning-time
ownership of the boot path; *recovery* of a broken/unbootable GRUB from rescue
media belongs to `linux-disaster-recovery`.

```bash
# List installed kernels; mark the running one and the GRUB default
sudo sk-kernel-rollback --list

# After booting a prior kernel from the GRUB menu post-panic, make it the default
sudo sk-kernel-rollback                 # interactive pick + confirm
sudo sk-kernel-rollback --to 5.15.0-91-generic

# Regenerate GRUB after editing /etc/default/grub
sudo update-grub                         # Debian/Ubuntu
sudo grub2-mkconfig -o /boot/grub2/grub.cfg   # RHEL family
```

Full model, per-family commands, and the post-panic rollback workflow:
`references/grub2-and-kernel-rollback.md`

---

## Optional fast path (when sk-* scripts are installed)

After the basic OS and linux-skills are in place, running
`sudo install-skills-bin linux-server-provisioning` installs:

| Task | Fast-path script |
|---|---|
| Guided wizard for sections 1–11 | `sudo sk-provision-fresh` |
| List kernels / roll back to a known-good kernel | `sudo sk-kernel-rollback [--list \| --to <version>]` |

These are optional wrappers — every action is also a plain command documented in
the sections and references above.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-server-provisioning
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-provision-fresh | scripts/sk-provision-fresh.sh | no | Guided fresh-server wizard covering hostname, timezone, admin user, SSH, UFW, fail2ban, unattended-upgrades, certbot, and linux-skills clone. |
| sk-kernel-rollback | scripts/sk-kernel-rollback.sh | no | List installed kernels and set a chosen prior kernel as the GRUB2 default (grubby on RHEL, grub-set-default + update-grub on Debian). Read-only with --list; asks before changing the default; never removes a kernel. |
