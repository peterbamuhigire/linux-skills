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
