# Linux Skills Knowledge Base

This repository contains Linux skills, commands, tips, and notes.
Claude Code reads this repo automatically at the start of every session.

## Structure

- `linux-sysadmin/` - Hub skill: routes to all specialist skills (start here)
- `linux-*/` - Specialist skills: security, provisioning, deployment, services, etc.
- `commands/` - Useful command references organized by topic
- `scripts/` - Reusable shell scripts and snippets
- `notes/` - General Linux notes and troubleshooting guides

## Skills

This repo IS the Claude Code skills directory. On a server it is cloned to
`~/.claude/skills` so all skills load automatically. Run `scripts/setup-claude-code.sh`
on a new server to set everything up.

Available skills (use `linux-sysadmin` as the entry point):
- `linux-sysadmin` — hub, routes to all 14 below
- `linux-security-analysis` — 10-layer security audit
- `linux-server-hardening` — harden SSH, UFW, sysctl, web stack
- `linux-server-provisioning` — provision a fresh Ubuntu/Debian server
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

## Key Rules

- **New repo on server?** It MUST be added to both `/usr/local/bin/update-all-repos` and `/usr/local/bin/update-repos`. See `notes/new-repo-checklist.md` for instructions.
