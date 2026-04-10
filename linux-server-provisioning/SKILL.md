---
name: linux-server-provisioning
description: Set up a fresh Ubuntu/Debian server from scratch for production web hosting. Interactive step-by-step. Covers hostname, timezone, admin user, SSH hardening, UFW, full stack installation (Nginx, Apache port 8080, PHP-FPM, MySQL 8, PostgreSQL, Redis, Node.js, fail2ban, certbot, rclone, msmtp), Nginx snippet setup, and post-install security verification.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Server Provisioning

**This skill is self-contained.** The 11-section manual procedure below uses
only standard Ubuntu/Debian tools. The `sk-provision-fresh` script in the
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

## Optional fast path (when sk-* scripts are installed)

After the basic OS and linux-skills are in place, running
`sudo install-skills-bin linux-server-provisioning` installs:

| Task | Fast-path script |
|---|---|
| Guided wizard for sections 1–11 | `sudo sk-provision-fresh` |

This is an optional wrapper around the 11 manual sections above.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-server-provisioning
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-provision-fresh | scripts/sk-provision-fresh.sh | no | Guided fresh-server wizard covering hostname, timezone, admin user, SSH, UFW, fail2ban, unattended-upgrades, certbot, and linux-skills clone. |
