---
name: linux-sysadmin
description: Linux server management hub for Ubuntu/Debian production servers. Use for any server management task — security analysis, hardening, services, deployment, monitoring, troubleshooting, disaster recovery, networking, mail, virtualization, secrets, observability. Routes to the right specialist skill.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Linux Server Admin Hub

## Use when

- The user has a Linux server task but has not yet chosen the right specialist skill.
- You need routing across provisioning, security, networking, operations, recovery, or script work.
- You need the default repo-wide operating rules before entering a narrower workflow.

## Do not use when

- The task is already clearly scoped to a specialist skill below and you can move there directly.
- The task is about authoring or reviewing `sk-*` scripts; load `linux-bash-scripting`.

## Required inputs

- The server role or symptom the user is dealing with.
- Whether the task is read-only analysis or a system-changing action.
- Any known constraints such as production impact, maintenance window, or missing access.

## Workflow

1. Classify the task using the routing table.
2. Load the matching specialist skill and follow its manual workflow as the source of truth.
3. Use the optional `sk-*` scripts only when they are installed and fit the task.
4. Verify the result with service checks, config validation, or follow-up inspection before closing.

## Quality standards

- Route quickly and explicitly; do not leave the user in the hub longer than necessary.
- Preserve the repo's safety rules: confirm destructive work, validate configs before reload, and prefer idempotent changes.
- Keep script guidance aligned with `docs/engine-design/spec.md`.

## Anti-patterns

- Trying to solve every task from the hub instead of handing off to a specialist skill.
- Guessing which skill applies without checking the routing table.
- Assuming scripts are installed or that a task must use automation when manual steps are available.

## Outputs

- The selected specialist skill.
- The next manual workflow or script entry point to run.
- The verification step needed to prove the task is complete.

## References

- [`docs/engine-design/spec.md`](../docs/engine-design/spec.md)
- [`docs/engine-design/script-inventory.md`](../docs/engine-design/script-inventory.md)

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
Deployment:sk-update-all-repos (git reset --hard + optional build)
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

  SECURITY
   4.  Security analysis (deep read-only audit + severity report)
   5.  Security hardening (apply fixes interactively)
   6.  Manage users & access control
   7.  Firewall & SSL certificates
   8.  Intrusion detection (fail2ban, AIDE, auditd)
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
  19.  Virtualization (LXD, Docker, KVM)
  20.  Configuration management (Ansible, drift detection)
  21.  Observability (Prometheus, log shipping, /health)

  RECOVERY
  22.  Troubleshoot an issue
  23.  Disaster recovery & restore from backup

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

## Standing Rules

- All skills work on any Ubuntu/Debian server — no product names in guidance.
- Confirm before every destructive operation (restore, drop, reset, delete).
  Use `confirm_destructive` from `common.sh` — requires the literal word `yes`.
- Run `sudo nginx -t` (or `sk-nginx-test-reload`) before every Nginx reload — never skip.
- Every new repo on the server MUST be registered in
  `/usr/local/bin/update-all-repos`.
- `update-all-repos` runs `git reset --hard` — local changes are destroyed on pull.
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
