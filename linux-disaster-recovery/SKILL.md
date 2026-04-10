---
name: linux-disaster-recovery
description: Restore from GPG-encrypted backups on Ubuntu/Debian servers. Covers MySQL database restore (single DB or full), app file restore, config snapshots, and emergency recovery checklist. Backups are AES256 GPG encrypted, stored locally and on Google Drive via rclone. Always confirms before any destructive restore.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Disaster Recovery

**Always confirm before restoring.** A restore overwrites existing data.
Every destructive restore runs `confirm_destructive` — the operator must
type the full word `yes`.

---

## Step 1: Assess First

```bash
sudo sk-service-health --failed
sudo sk-journal-errors --since 2h | head -20
```

Service crash → restart it (`linux-service-management`), no restore needed.
Data loss/corruption → proceed below.

## Step 2: Find The Right Backup

```bash
sudo sk-backup-verify      # is the most recent backup usable?
```

For manual inspection:

```bash
# Local backups (7-day retention)
ls -lth ~/backups/mysql/*.gpg 2>/dev/null | head -10

# Google Drive (3-day retention for MySQL)
rclone ls gdrive:<backup-folder> 2>/dev/null | sort | tail -10

# If rclone token expired:
rclone config reconnect gdrive:
```

Choose the backup **closest to before the incident**.

## Step 3: Restore

For a guided restore, run:

```bash
sudo sk-restore-wizard
```

It walks: pick backup set → pick restore target → preview → confirm → execute.

For direct script invocations:

```bash
sudo sk-mysql-restore --file /path/to/backup.gpg
sudo sk-postgres-restore --file /path/to/backup.gpg
sudo sk-site-restore --backup /path/to/site-backup.tar.gpg --target /var/www/html/example
```

Full manual restore procedure: `references/restore-procedures.md`

## Emergency Checklist

```bash
# 1. Drop to maintenance mode (Nginx 503 page, stop non-essentials)
sudo sk-emergency-mode on

# 2. Stop affected service to prevent further damage
sudo systemctl stop <service>

# 3. Find best backup
sudo sk-backup-verify

# 4. Decrypt → restore → verify
sudo sk-restore-wizard

# 5. Restart all services
sudo sk-service-restart nginx mysql php8.3-fpm apache2

# 6. Re-run security audit
sudo sk-audit

# 7. Exit maintenance mode
sudo sk-emergency-mode off
```

## Demo/Dev Reset (Git-Tracked SQL Dump Pattern)

Some apps ship a git-tracked SQL dump as the demo DB source of truth.
A reset script drops and recreates from that dump:

```bash
ls /usr/local/bin/reset-*           # find available reset scripts
sudo reset-<app>-from-git           # requires typing YES
ls /var/backups/<app>/              # safety backup always created first
```

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-disaster-recovery
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-backup-verify | scripts/sk-backup-verify.sh | yes | Verify last backup age, integrity (tar/gpg check), remote copy reachable via rclone. |
| sk-mysql-backup | scripts/sk-mysql-backup.sh | no | Dump all databases with gzip + gpg + rclone upload; rotate local and remote. |
| sk-mysql-restore | scripts/sk-mysql-restore.sh | no | Guided restore: list backups, pick, download, decrypt, show sizes, confirm, restore. |
| sk-postgres-backup | scripts/sk-postgres-backup.sh | no | `pg_dump` + compression + gpg + rclone, per database or all, with rotation. |
| sk-postgres-restore | scripts/sk-postgres-restore.sh | no | Guided PostgreSQL restore from backup file or remote. |
| sk-site-backup | scripts/sk-site-backup.sh | no | Tar a full site directory, exclude cache/node_modules, gpg, upload via rclone. |
| sk-site-restore | scripts/sk-site-restore.sh | no | Restore a site backup to original path with permission repair. |
| sk-config-snapshot | scripts/sk-config-snapshot.sh | no | Snapshot `/etc/` (and other declared dirs) to a git-tracked archive; diff against previous. |
| sk-restore-wizard | scripts/sk-restore-wizard.sh | no | Interactive guided restore: pick backup set, pick target, preview, confirm, execute. |
| sk-emergency-mode | scripts/sk-emergency-mode.sh | no | Toggle maintenance mode: drop Nginx to 503 page, stop non-essential services, show live status. |
