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

**This skill is self-contained.** Every command below works on a stock
Ubuntu/Debian server with no additional tooling. The `sk-*` scripts in the
**Optional fast path** section at the bottom are convenience wrappers —
they are never required.

Ask: "What's the symptom?" then follow the matching branch in
`references/diagnosis-tree.md`.

## Symptom Index

| Symptom | Branch |
|---------|--------|
| High CPU or load average | → Branch 1 |
| Out of memory / OOM kill | → Branch 2 |
| Disk full | → Branch 3 |
| Service crashed / won't start | → Branch 4 |
| 502 or 504 from Nginx | → Branch 5 |
| Site is slow | → Branch 6 |
| MySQL problems | → Branch 7 |
| SSL expired or renewal failed | → Branch 8 |
| Backup failed | → Branch 9 |
| Site down after update-all-repos | → Branch 10 |
| Can't reach this server | → Branch 11 |

Full diagnosis commands for each: `references/diagnosis-tree.md`

---

## Quick Triage (Run First For Any Issue)

```bash
# System health snapshot
uptime && free -h && df -h

# Failed services
sudo systemctl list-units --type=service --state=failed

# Recent errors across all services
sudo journalctl -p err --since "1 hour ago" --no-pager | head -30

# Nginx error log
sudo tail -20 /var/log/nginx/error.log
```

---

## Most Common Fixes

```bash
# Service crashed → restart it
sudo systemctl restart <service>

# Nginx config broken → find and fix
sudo nginx -t

# Disk full → clear apt cache and vacuum journal
sudo apt clean && sudo journalctl --vacuum-size=500M

# 502 → restart the upstream
sudo systemctl restart php8.3-fpm
sudo systemctl restart apache2

# SSL expired → force renew
sudo certbot renew --force-renewal
```

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-troubleshooting` gives you
interactive decision-tree walkers for each symptom:

| Symptom | Fast-path script |
|---|---|
| High CPU / slow site | `sudo sk-load-investigate` → `sudo sk-why-slow` |
| 502 / 504 | `sudo sk-why-500` |
| Can't reach server | `sudo sk-why-cant-connect` |

These scripts wrap the manual commands above in a guided walkthrough.
They are optional — the manual commands are always the source of truth.

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
