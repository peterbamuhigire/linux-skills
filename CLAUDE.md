# Linux Skills Knowledge Base

This repository contains Linux skills, commands, tips, and notes.
Claude Code reads this repo automatically at the start of every session.

## Two-family engine (read this first)

This is a **two-family** engine: every skill and `sk-*` script supports both
**Debian/Ubuntu** and the **RHEL family** (Fedora, RHEL, CentOS Stream, Rocky,
Alma, Oracle).

- Each specialist skill leads with a **`## Distro support`** matrix mapping
  Debian/Ubuntu commands/paths/services to their RHEL-family equivalents.
- **Never hardcode `apt`/`ufw`/`apache2` in a script.** Use the `common.sh`
  primitives: `detect_distro`, `pkg_install`, `pkg_is_installed`, `ensure_epel`,
  `svc_name`, `firewall_allow`, `web_conf_dir`, `web_reload`, and
  `require_family <debian|rhel|any>`.
- The big family differences are SELinux (vs AppArmor), firewalld (vs UFW),
  `httpd`+conf.d (vs apache2+sites-available), NetworkManager (vs Netplan),
  dnf-automatic (vs unattended-upgrades), `wheel` (vs `sudo`), and Kickstart
  (vs autoinstall). Deep-dive references live under the relevant skills.
- Plan, phasing, and status: [`docs/multi-distro/plan.md`](docs/multi-distro/plan.md).
- Invariant: `scripts/tests/check-distro-matrix.sh` asserts every specialist
  skill carries a Distro support matrix — run it after adding/editing a skill.

## Structure

- `linux-sysadmin/` - Hub skill: routes to all specialist skills (start here)
- `NN-category/linux-*/` - Specialist skills grouped into numbered categories:
  `01-provisioning-and-bootstrap`, `02-users-access-and-secrets`, `03-networking-and-dns`,
  `04-web-and-mail-services`, `05-services-and-virtualization`, `06-storage-and-filesystems`,
  `07-security-and-hardening`, `08-observability-and-logging`, `09-troubleshooting-and-recovery`,
  `10-automation-and-scripting`
- `meta/` - Engine-authoring skills (`skill-writing`, `skill-safety-audit`)
- `commands/` - Useful command references organized by topic
- `scripts/` - Reusable shell scripts and snippets
- `notes/` - General Linux notes and troubleshooting guides

## Skills

This repo IS the Claude Code skills directory. On a server it is cloned to
`~/.claude/skills` so all skills load automatically. Run `scripts/setup-claude-code.sh`
on a new server to set everything up.

Available skills (use `linux-sysadmin` as the entry point):
- `linux-sysadmin` — hub, routes to all 24 specialist skills below
- `linux-bash-scripting` — **meta-skill.** Canonical script template, `common.sh` library contract, standard flags, interactive UX rules. Load before writing or reviewing any `sk-*` script.
- `linux-security-analysis` — 10-layer security audit
- `linux-server-hardening` — harden SSH, UFW, sysctl, web stack
- `linux-server-provisioning` — provision a fresh Debian/Ubuntu or RHEL-family server
- `linux-site-deployment` — deploy sites (static, PHP, Node.js)
- `linux-service-management` — manage and diagnose systemd services
- `linux-troubleshooting` — symptom-based diagnosis trees
- `linux-disaster-recovery` — restore from backup, emergency procedures
- `linux-firewall-ssl` — UFW rules, certbot, TLS config
- `linux-intrusion-detection` — fail2ban, AIDE, auditd
- `linux-webstack` — Nginx + Apache + PHP-FPM + Node.js
- `linux-access-control` — users, SSH keys, file permissions
- `linux-system-monitoring` — CPU, memory, disk, network health
- `linux-disk-storage` — disk usage, cleanup, inode issues
- `linux-log-management` — journalctl, Nginx/Apache logs, logrotate
- `linux-network-admin` — interfaces, routes, netplan, DNS client, NTP
- `linux-dns-server` — authoritative DNS (bind9 / unbound)
- `linux-mail-server` — Postfix / Exim, SPF/DKIM/DMARC, mail queue
- `linux-virtualization` — LXD, Docker, KVM container & VM lifecycle
- `linux-cloud-init` — cloud-init user-data and Ubuntu autoinstall
- `linux-package-management` — apt, snap, unattended-upgrades
- `linux-config-management` — Ansible, drift detection, `/etc` tracking
- `linux-observability` — Prometheus node_exporter, log shipping, `/health`
- `linux-secrets` — secret scanning, rotation, age/sops

## Engine design

- All conventions live in [`docs/engine-design/spec.md`](docs/engine-design/spec.md).
- The curated script catalogue (~88 scripts) is in [`docs/engine-design/script-inventory.md`](docs/engine-design/script-inventory.md).
- Scripts install to `/usr/local/bin/` with the `sk-` prefix via `install-skills-bin`.
- Hybrid install: `sudo install-skills-bin core` at setup, per-skill lazy install on first use.
- Every script sources `/usr/local/lib/linux-skills/common.sh`.

## Key Rules

- **Two-family by default.** Every new or edited specialist skill MUST carry a `## Distro support` matrix (Debian/Ubuntu ↔ RHEL family) as its first H2, and every `sk-*` script MUST use the `common.sh` distro primitives instead of hardcoding a package manager / firewall / web server. Run `scripts/tests/check-distro-matrix.sh` to verify.
- **Author attribution is mandatory.** Every SKILL.md, script, and generated document must credit **Peter Bamuhigire** (techguypeter.com, +256784464178) — in SKILL.md frontmatter `metadata.author`, in script `#: Author:` headers, and in doc footers.
- **Scripts track skills automatically.** When a skill's knowledge changes (new Ubuntu version, better approach, updated standard), proactively update every affected script in the same session — do not wait to be told.
- **New repo on server?** It MUST be added to both `/usr/local/bin/update-all-repos` and `/usr/local/bin/update-repos`. See `notes/new-repo-checklist.md` for instructions.
- **First use of a skill on a new server?** Run `sudo install-skills-bin <skill-name>` to install that skill's scripts into `/usr/local/bin/`. For initial server setup, run `sudo install-skills-bin core` to install the tier-1 foundation scripts.
