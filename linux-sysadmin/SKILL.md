---
name: linux-sysadmin
description: Use when a Debian/Ubuntu or RHEL-family server request needs routing across provisioning, security, services, networking, recovery, databases, containers, storage, performance, or compliance; use linux-troubleshooting when an unexplained symptom spans components.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
  portable: true
  compatible_with:
    - claude-code
    - codex
---
# Linux Server Admin Hub

<!-- dual-compat-start -->
## Use When

- The user has a Linux server task but has not yet chosen the right specialist skill.
- You need routing across provisioning, security, networking, operations, recovery, or script work.
- You need the default repo-wide operating rules before entering a narrower workflow.

## Do Not Use When

- The task is already clearly scoped to a specialist skill below and you can move there directly.
- The task is about authoring or reviewing `sk-*` scripts; load `linux-bash-scripting`.

## Required Inputs

| Artefact | Source | Required? | If absent |
|---|---|---:|---|
| Server role, intended outcome, or observed symptom | User request | yes | Ask for or gather only the context needed to route safely. |
| Distro family and version | `/etc/os-release` or user | conditional | Route provisionally and require detection before family-specific commands. |
| Authority boundary and operational constraints | User and environment | yes for mutation | Default to read-only diagnosis; do not infer production-change authority. |

## Workflow

1. Classify the task using the routing table.
2. Load the matching specialist skill and follow its manual workflow as the source of truth.
3. Use the optional `sk-*` scripts only when they are installed and fit the task.
4. Stop before destructive, externally visible, or production-changing work that lacks explicit authority.
5. If the first route fails, recover by returning to the observed symptom and select the nearest diagnostic skill rather than guessing a repair.
6. Verify the result with service checks, config validation, or follow-up inspection before closing.

7. For an engine or product audit, load `meta/kaizen-improvement-system/SKILL.md`, publish the raw dimensions with a hard-capped maximum of 65/100, and create a 95/100 improvement plan. For current distro, security, compliance, vendor, or platform claims, route through the `digital-research-skills` engine before standardising.

## Quality Standards

- Route quickly and explicitly; do not leave the user in the hub longer than necessary.
- Preserve the repo's safety rules: confirm destructive work, validate configs before reload, and prefer idempotent changes.
- Keep script guidance aligned with `docs/engine-design/spec.md`.

## Anti-Patterns

- Solving a database backup from the hub. Fix: hand off to `linux-mysql-mariadb` or `linux-postgresql` and follow its evidence contract.
- Guessing a route from one keyword. Fix: compare the requested outcome with the nearest neighbour descriptions.
- Assuming an `sk-*` command is installed. Fix: keep the manual procedure as the baseline and verify any accelerator before use.
- Treating an unknown distro as Ubuntu. Fix: detect the family before selecting packages, paths, services, firewall, or MAC controls.
- Turning a request for analysis into an authorised repair. Fix: keep the first pass read-only unless mutation is explicit.
- Claiming completion after a command exits zero. Fix: inspect the service, configuration, logs, backup, or system state named by the specialist acceptance condition.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Ranked specialist route | Operator or downstream agent | Primary skill is named and the closest rejected neighbour is explained when ambiguous. |
| Authority and context handoff | Selected specialist | Distro, server role, change boundary, and missing evidence are explicit. |
| Verification target | Operator | A concrete service, configuration, log, backup, or system state proves completion. |

## Evidence Produced

| Category | Artefact | Acceptance condition |
|---|---|---|
| Routing | Route record | Selected skill, trigger evidence, neighbour distinction, and verification target are present. |

<!-- dual-compat-end -->

## Capability Contract

Routing requires read access to the request and skill catalogue. System inspection is read-only by default. Editing, package changes, service reloads, network changes, destructive actions, and production mutation are governed by the selected specialist and require explicit authority.

## Degraded Mode

If the server or catalogue cannot be inspected, return the top three plausible skills with the missing fact that separates them. Do not issue family-specific or mutating commands and do not treat unobserved system state as healthy.

## Decision Rules

| Choice | Route or action | Failure or risk avoided |
|---|---|---|
| Cause is unknown and symptom spans components | `linux-troubleshooting` first | Premature repair of the wrong subsystem |
| User asks for a security posture report | `linux-security-analysis` read-only | Accidental hardening changes during assessment |
| User explicitly asks to apply security fixes | `linux-server-hardening` | Audit workflow that cannot implement authorised repairs |
| Work creates or reviews an `sk-*` script | `linux-bash-scripting` before domain skill | Distro-specific and unsafe script drift |

## Worked Example

"The website is returning 502 after a PHP upgrade" routes first to `linux-webstack`, with `linux-service-management` and `linux-log-management` as neighbours. The handoff records the distro family, affected virtual host, recent package change, and a read-only first pass before any reload.

## References

- [`docs/engine-design/spec.md`](../docs/engine-design/spec.md)
- [`docs/engine-design/script-inventory.md`](../docs/engine-design/script-inventory.md)
- [`meta/kaizen-improvement-system/SKILL.md`](../meta/kaizen-improvement-system/SKILL.md)
- [`docs/continuous-improvement/linux-product-audit-checklist.md`](../docs/continuous-improvement/linux-product-audit-checklist.md)
- [`docs/continuous-improvement/two-family-validation-and-recovery.md`](../docs/continuous-improvement/two-family-validation-and-recovery.md)

## Server Context

This context applies to the primary managed server. Update when working on a
different server.

```
OS:        Ubuntu/Debian production server
Web:       Nginx (80/443) → PHP-FPM | Apache (8080) | Node.js services
DBs:       MySQL 8 | PostgreSQL 15 | Redis
Security:  UFW (22/80/443 only), fail2ban, SSH keys-only, certbot ECDSA certs
Backups:   Cron → backup-alert.sh → GPG AES256 → rclone → Google Drive
           Local: 7 days | Remote: 3 days | Credentials: mode 600
Deployment:sk-update-all-repos (pull --rebase --autostash + optional build)
Admin:     /home/administrator | Web: /var/www/html/ and /var/www/
Nginx cfg: /etc/nginx/sites-available/*.conf | snippets: /etc/nginx/snippets/
Toolkit:   /usr/local/bin/sk-* (installed by install-skills-bin)
Library:   /usr/local/lib/linux-skills/common.sh
Logs:      /var/log/linux-skills/
```

## Engine design

All scripts and skills in this repo follow the conventions in
[`docs/engine-design/spec.md`](../docs/engine-design/spec.md). The curated
catalogue of ~88 scripts lives in
[`docs/engine-design/script-inventory.md`](../docs/engine-design/script-inventory.md).
Before writing or reviewing a script, load `linux-bash-scripting`.

## What Do You Need To Do?

This hub routes to all **40 specialist skills**, organized into **15
categories** (01-15), plus the `linux-bash-scripting` meta-skill (choice 0).

```
Linux Server Management
═══════════════════════════════════════════════════════

  FOUNDATION
   0.  Write or review a script (the meta-skill)

  PROVISIONING & DEPLOYMENT
   1.  Set up a new server (from scratch)
   2.  Bootstrap with cloud-init / autoinstall YAML
   3.  Deploy a new website
  14.  Manage packages (apt, snap, unattended-upgrades)
  24.  Safely update git repos (never destroy local work)

  SECURITY
   4.  Security analysis (deep read-only audit + severity report)
   5.  Security hardening (apply fixes interactively)
   6.  Manage users & access control
   7.  Firewall & SSL certificates
   8.  Intrusion detection (fail2ban, active response)
  15.  Secrets (scanning, rotation, age/sops)

  OPERATIONS
   9.  Manage services (nginx, mysql, php-fpm, cron…)
  10.  Disk & storage management
  11.  Monitor system health
  12.  Web stack (Nginx, Apache, PHP-FPM, Node.js)
  13.  Log management & analysis

  NETWORKING
  16.  Networking (interfaces, netplan, DNS client, NTP)
  17.  DNS server (bind9 / unbound)
  18.  Mail server (Postfix / Exim, SPF/DKIM/DMARC)

  CONTAINERS & AUTOMATION
  19.  Virtualization (KVM/libvirt, LXD)
  20.  Configuration management (Ansible, drift detection)
  21.  Observability (Prometheus, log shipping, /health)

  RECOVERY
  22.  Troubleshoot an issue
  23.  Disaster recovery & restore from backup

  DATABASES & CACHING
  25.  MySQL / MariaDB (install, tune, backup)
  26.  PostgreSQL (install, tune, backup)
  27.  In-memory stores (Redis, Memcached)

  CONTAINERS & ORCHESTRATION
  28.  Container engine (Docker / Podman install & management)
  29.  Container deployment (run & operate containers)
  30.  Image hygiene (reclaim disk from the container engine)

  BACKUP & ARCHIVING
  31.  rsync sync (offsite & incremental backups)
  32.  Archive integrity (tar.gz / tar.xz create + verify)
  33.  Filesystem snapshots (point-in-time snapshots)

  PERFORMANCE & KERNEL
  34.  sysctl tuning (performance kernel tuning)
  35.  Kernel modules (drivers)
  36.  perf profiling (find the bottleneck before tuning)

  COMPLIANCE & AUDITING
  37.  auditd rules (audit daemon for compliance/forensics)
  38.  File integrity (FIM with AIDE)
  39.  Benchmark scanning (security-benchmark / compliance scans)

═══════════════════════════════════════════════════════
```

## Routing Table

| Choice | Skill |
|--------|-------|
| 0 | linux-bash-scripting |
| 1 | linux-server-provisioning |
| 2 | linux-cloud-init |
| 3 | linux-site-deployment |
| 4 | linux-security-analysis |
| 5 | linux-server-hardening |
| 6 | linux-access-control |
| 7 | linux-firewall-ssl |
| 8 | linux-intrusion-detection |
| 9 | linux-service-management |
| 10 | linux-disk-storage |
| 11 | linux-system-monitoring |
| 12 | linux-webstack |
| 13 | linux-log-management |
| 14 | linux-package-management |
| 15 | linux-secrets |
| 16 | linux-network-admin |
| 17 | linux-dns-server |
| 18 | linux-mail-server |
| 19 | linux-virtualization |
| 20 | linux-config-management |
| 21 | linux-observability |
| 22 | linux-troubleshooting |
| 23 | linux-disaster-recovery |
| 24 | linux-repo-sync |
| 25 | linux-mysql-mariadb |
| 26 | linux-postgresql |
| 27 | linux-inmemory-stores |
| 28 | linux-container-engine |
| 29 | linux-container-deployment |
| 30 | linux-image-hygiene |
| 31 | linux-rsync-sync |
| 32 | linux-archive-integrity |
| 33 | linux-filesystem-snapshots |
| 34 | linux-sysctl-tuning |
| 35 | linux-kernel-modules |
| 36 | linux-perf-profiling |
| 37 | linux-auditd-rules |
| 38 | linux-file-integrity |
| 39 | linux-benchmark-scanning |

## Standing Rules

- All skills work on any Ubuntu/Debian server — no product names in guidance.
- Confirm before every destructive operation (restore, drop, reset, delete).
  Use `confirm_destructive` from `common.sh` — requires the literal word `yes`.
- Run `sudo nginx -t` (or `sk-nginx-test-reload`) before every Nginx reload — never skip.
- Every new repo on the server MUST be registered in
  `/usr/local/bin/update-all-repos`.
- Repo-update scripts MUST preserve local work. Use
  `git pull --rebase --autostash` plus a `git status --porcelain` dirty-check;
  NEVER `git reset --hard` or `git clean -fd` in an automated/menu updater.
  See `linux-repo-sync` — this is a binding standard on every server.
- Backup credential files must always be mode 600.
- Every `sk-*` script follows the conventions in
  [`docs/engine-design/spec.md`](../docs/engine-design/spec.md) and sources
  `/usr/local/lib/linux-skills/common.sh`.
- On a fresh server, run `sudo install-skills-bin core` once during setup.
  Individual skills lazy-install their own scripts on first use.
- When a skill's knowledge changes, affected scripts are updated
  automatically in the same session — scripts and skills stay in lockstep.

## Install on a new server

```bash
# As the admin user, clone linux-skills and run the setup script:
git clone git@github.com:<org>/linux-skills.git ~/.claude/skills
bash ~/.claude/skills/scripts/setup-claude-code.sh

# Then install the core sk-* scripts into /usr/local/bin:
sudo install-skills-bin core
```
