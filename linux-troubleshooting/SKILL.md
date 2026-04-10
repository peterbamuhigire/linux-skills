---
name: linux-troubleshooting
description: Systematic incident diagnosis for Ubuntu/Debian production servers. Ask for the symptom then follow the matching diagnosis branch — high CPU/load, OOM kill, disk full, service crashed, 502/504 errors, slow site, MySQL issues, SSL expired, backup failed, site down after git update.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Troubleshooting

Ask: "What's the symptom?" then follow the branch in `references/diagnosis-tree.md`,
or run the matching `sk-why-*` script which walks the tree interactively.

## Symptom Index

| Symptom | Script | Branch |
|---|---|---|
| High CPU or load average | `sk-load-investigate` → `sk-why-slow` | → Branch 1 |
| Out of memory / OOM kill | `sk-why-slow` | → Branch 2 |
| Disk full | `sk-disk-hogs` | → Branch 3 |
| Service crashed / won't start | `sk-service-health <svc>` | → Branch 4 |
| 502 or 504 from Nginx | `sk-why-500` | → Branch 5 |
| Site is slow | `sk-why-slow` | → Branch 6 |
| MySQL problems | `sk-why-500 --focus mysql` | → Branch 7 |
| SSL expired or renewal failed | `sk-cert-status` → `sk-cert-renew` | → Branch 8 |
| Backup failed | `sk-backup-verify` | → Branch 9 |
| Site down after update-all-repos | `sk-why-500` | → Branch 10 |
| Can't reach this server | `sk-why-cant-connect` | → Branch 11 |

Full diagnosis commands for each: `references/diagnosis-tree.md`

---

## Quick Triage (Run First For Any Issue)

```bash
sudo sk-system-health             # single-screen overview
sudo sk-service-health --failed   # only failed services
sudo sk-journal-errors --since 1h # recent errors across all services
```

---

## Most Common Fixes

```bash
# Service crashed → restart it safely
sudo sk-service-restart <service>

# Nginx config broken → find and fix
sudo sk-nginx-test-reload

# Disk full → interactive cleanup
sudo sk-disk-cleanup

# 502 → restart the upstream
sudo sk-service-restart php8.3-fpm
sudo sk-service-restart apache2

# SSL expired → force renew
sudo sk-cert-renew --domain example.com
```

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-troubleshooting
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-load-investigate | scripts/sk-load-investigate.sh | no | Decompose load average: CPU-bound vs I/O-bound vs blocked, top offenders per category. |
| sk-why-slow | scripts/sk-why-slow.sh | no | Decision-tree entry point: walks load/CPU/memory/disk/network/database to diagnose slowness. |
| sk-why-500 | scripts/sk-why-500.sh | no | Decision-tree: PHP-FPM up? Nginx up? error log? permissions? AppArmor? disk full? |
| sk-why-cant-connect | scripts/sk-why-cant-connect.sh | no | Decision-tree: firewall? service listening? DNS? routing? cert expired? rate-limited by fail2ban? |
