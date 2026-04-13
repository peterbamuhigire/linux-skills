# linux-skills

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

A Linux server management engine for Ubuntu/Debian production servers. This
repo is a curated knowledge base of **24 specialist skills**, a detailed
engine specification, and (soon) a suite of ~88 interactive, secure
`sk-*` scripts that wrap the skills in command-line form.

The repository is designed to remain fully usable in **Claude Code** while
also working cleanly in **Codex**. `SKILL.md` is the portable unit; `CLAUDE.md`
and [`AGENTS.md`](AGENTS.md) provide host-specific guidance layered on top.

## Structure

```
docs/engine-design/      Engine specification + curated script inventory
linux-bash-scripting/    Meta-skill: how every sk-* script is written
linux-<domain>/          23 specialist skills, each with SKILL.md + references/
scripts/                 Executable scripts (sk-* + legacy)
commands/                Command references by topic
notes/                   Setup guides and troubleshooting
```

## Start here

1. **Read the engine design first.** Every script and skill in this repo
   obeys the conventions in [`docs/engine-design/spec.md`](docs/engine-design/spec.md).
   The curated catalogue of scripts lives in
   [`docs/engine-design/script-inventory.md`](docs/engine-design/script-inventory.md).
2. **Use `linux-sysadmin` as the routing hub.** It's the entry point that
   maps "what do you want to do?" to the right specialist skill.
3. **For Codex or other non-Claude agents, read [`AGENTS.md`](AGENTS.md).**
   It explains repo purpose, routing, and working rules without changing the
   existing layout.
4. **Install on a fresh server** with
   [`scripts/setup-claude-code.sh`](scripts/setup-claude-code.sh), then
   `sudo install-skills-bin core` (once the installer ships).

## The 24 skills

**Foundation**
- [`linux-bash-scripting`](linux-bash-scripting/SKILL.md) — meta-skill. The
  canonical script template, `common.sh` library contract, standard flags,
  interactive UX rules, safety patterns. Load this before writing or
  reviewing any `sk-*` script.
- [`linux-sysadmin`](linux-sysadmin/SKILL.md) — the routing hub.

**Security**
- [`linux-security-analysis`](linux-security-analysis/SKILL.md) — 10-layer
  read-only audit.
- [`linux-server-hardening`](linux-server-hardening/SKILL.md) — apply fixes
  interactively.
- [`linux-access-control`](linux-access-control/SKILL.md) — users, SSH keys,
  file permissions.
- [`linux-firewall-ssl`](linux-firewall-ssl/SKILL.md) — UFW, certbot, TLS.
- [`linux-intrusion-detection`](linux-intrusion-detection/SKILL.md) —
  fail2ban, AIDE, auditd.
- [`linux-secrets`](linux-secrets/SKILL.md) — scanning, age/sops, rotation.

**Operations**
- [`linux-server-provisioning`](linux-server-provisioning/SKILL.md) — fresh
  server setup.
- [`linux-cloud-init`](linux-cloud-init/SKILL.md) — cloud-init user-data and
  Ubuntu autoinstall.
- [`linux-site-deployment`](linux-site-deployment/SKILL.md) — deploy sites
  (static, PHP, Astro).
- [`linux-service-management`](linux-service-management/SKILL.md) — systemd.
- [`linux-webstack`](linux-webstack/SKILL.md) — Nginx + Apache + PHP-FPM +
  Node.js.
- [`linux-package-management`](linux-package-management/SKILL.md) — apt,
  snap, unattended-upgrades.
- [`linux-disk-storage`](linux-disk-storage/SKILL.md) — usage, cleanup,
  inodes, swap.
- [`linux-system-monitoring`](linux-system-monitoring/SKILL.md) — CPU,
  memory, disk, network health.
- [`linux-log-management`](linux-log-management/SKILL.md) — journalctl,
  access/error logs, logrotate.

**Networking**
- [`linux-network-admin`](linux-network-admin/SKILL.md) — interfaces,
  routes, netplan, DNS client, NTP.
- [`linux-dns-server`](linux-dns-server/SKILL.md) — authoritative DNS (BIND,
  unbound).
- [`linux-mail-server`](linux-mail-server/SKILL.md) — Postfix, Exim, SPF,
  DKIM, DMARC.

**Containers & automation**
- [`linux-virtualization`](linux-virtualization/SKILL.md) — LXD, Docker,
  KVM.
- [`linux-config-management`](linux-config-management/SKILL.md) — Ansible,
  drift detection, /etc tracking.
- [`linux-observability`](linux-observability/SKILL.md) — Prometheus
  node_exporter, log shipping, /health.

**Recovery**
- [`linux-troubleshooting`](linux-troubleshooting/SKILL.md) — symptom-based
  diagnosis trees.
- [`linux-disaster-recovery`](linux-disaster-recovery/SKILL.md) — restore
  from backup, emergency procedures.

## Design principles

- **Skills are self-contained.** Every skill works on a stock Ubuntu/Debian
  server using only built-in tools. The `sk-*` scripts are an *optional
  fast path* — never a dependency.
- **Scripts track skill updates.** When a skill's knowledge changes, the
  affected scripts are updated in the same session. Skills and scripts
  stay in lockstep.
- **Idempotency by default.** Every script that mutates state is safe to
  run twice.
- **Author attribution is mandatory.** Every file credits Peter Bamuhigire.

## Current status

- 24 skills written (this session).
- Engine specification and curated 88-script inventory committed
  (`docs/engine-design/`).
- 3 existing scripts in `scripts/` (`server-audit.sh`, `mysql-backup.sh`,
  `update-all-repos`) — the 85 remaining scripts will be built in a
  follow-up session.

## Legacy content

- [update-all-repos](scripts/update-all-repos) — mandatory on every
  managed server. Pulls every registered repo.
- [mysql-backup.sh](scripts/mysql-backup.sh) — GPG-encrypted MySQL backups
  with rclone upload.
- [server-audit.sh](scripts/server-audit.sh) — the existing 14-section
  audit (will become `sk-audit`).
- [rclone](commands/rclone.md), [redis](commands/redis.md) — command
  references.
- [notes/](notes/) — setup guides for astro sites, mysql backups, redis,
  server security, new repo onboarding.
