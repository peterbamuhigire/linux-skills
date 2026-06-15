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
- `NN-category/linux-*/` - Specialist skills grouped into 15 numbered categories:
  `01-provisioning-and-bootstrap`, `02-users-access-and-secrets`, `03-networking-and-dns`,
  `04-web-and-mail-services`, `05-services-and-virtualization`, `06-storage-and-filesystems`,
  `07-security-and-hardening`, `08-observability-and-logging`, `09-troubleshooting-and-recovery`,
  `10-automation-and-scripting`, `11-databases-and-caching`, `12-containers-and-orchestration`,
  `13-backup-and-archiving`, `14-performance-and-kernel`, `15-compliance-and-auditing`
- `meta/` - Engine-authoring skills (`skill-writing`, `skill-safety-audit`)
- `commands/` - Useful command references organized by topic
- `scripts/` - Reusable shell scripts and snippets
- `notes/` - General Linux notes and troubleshooting guides

## Skills

This repo IS the Claude Code skills directory. On a server it is cloned to
`~/.claude/skills` so all skills load automatically. Run `scripts/setup-claude-code.sh`
on a new server to set everything up.

Available skills (use `linux-sysadmin` as the entry point):
- `linux-sysadmin` — hub, routes to all 40 specialist skills below (grouped into 15 categories)

**Meta / foundation**
- `linux-bash-scripting` — **meta-skill.** Canonical script template, `common.sh` library contract, standard flags, interactive UX rules. Load before writing or reviewing any `sk-*` script.

**01 — Provisioning & bootstrap**
- `linux-server-provisioning` — provision a fresh Debian/Ubuntu or RHEL-family server
- `linux-cloud-init` — cloud-init user-data, autoinstall, and Kickstart
- `linux-package-management` — apt, snap, unattended-upgrades / dnf, flatpak, dnf-automatic
- `linux-config-management` — Ansible, drift detection, `/etc` tracking

**02 — Users, access & secrets**
- `linux-access-control` — users, groups, SSH keys, sudo/wheel, file permissions
- `linux-secrets` — secret scanning, rotation, age/sops

**03 — Networking & DNS**
- `linux-network-admin` — interfaces, routes, netplan/NetworkManager, DNS client, NTP
- `linux-dns-server` — authoritative DNS (bind9 / unbound)

**04 — Web & mail services**
- `linux-webstack` — Nginx + Apache/httpd + PHP-FPM + Node.js
- `linux-site-deployment` — deploy sites (static, PHP, Node.js)
- `linux-mail-server` — Postfix / Exim, SPF/DKIM/DMARC, mail queue

**05 — Services & virtualization**
- `linux-service-management` — manage and diagnose systemd services
- `linux-virtualization` — KVM/libvirt VMs and LXD system containers

**06 — Storage & filesystems**
- `linux-disk-storage` — disk usage, cleanup, inode issues, swap

**07 — Security & hardening**
- `linux-security-analysis` — deep read-only security audit
- `linux-server-hardening` — harden SSH, firewall, sysctl, web stack
- `linux-firewall-ssl` — UFW/firewalld rules, certbot, TLS config
- `linux-intrusion-detection` — fail2ban and active intrusion response

**08 — Observability & logging**
- `linux-system-monitoring` — CPU, memory, disk, network health
- `linux-log-management` — journalctl, Nginx/Apache logs, logrotate
- `linux-observability` — Prometheus node_exporter, log shipping, `/health`

**09 — Troubleshooting & recovery**
- `linux-troubleshooting` — symptom-based diagnosis trees
- `linux-disaster-recovery` — restore from backup, emergency procedures

**10 — Automation & scripting**
- `linux-repo-sync` — safe git updates (`pull --rebase --autostash`)

**11 — Databases & caching**
- `linux-mysql-mariadb` — install, tune, and back up MySQL/MariaDB
- `linux-postgresql` — install, tune, and back up PostgreSQL
- `linux-inmemory-stores` — operate Redis and Memcached

**12 — Containers & orchestration**
- `linux-container-engine` — install/manage Docker (dockerd) or Podman
- `linux-container-deployment` — run and operate containers
- `linux-image-hygiene` — reclaim disk from the container engine

**13 — Backup & archiving**
- `linux-rsync-sync` — advanced rsync for offsite/incremental backups
- `linux-archive-integrity` — create and verify tar.gz / tar.xz archives
- `linux-filesystem-snapshots` — point-in-time filesystem snapshots

**14 — Performance & kernel**
- `linux-sysctl-tuning` — performance kernel tuning via sysctl
- `linux-kernel-modules` — manage kernel modules (drivers)
- `linux-perf-profiling` — find the bottleneck before tuning

**15 — Compliance & auditing**
- `linux-auditd-rules` — Linux Audit daemon (auditd) for compliance/forensics
- `linux-file-integrity` — File Integrity Monitoring (FIM) with AIDE
- `linux-benchmark-scanning` — security-benchmark / compliance scanning

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
