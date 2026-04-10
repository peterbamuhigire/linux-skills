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

**This skill is self-contained.** Every command below works on a stock
Ubuntu/Debian server. The `sk-*` scripts in the **Optional fast path**
section at the bottom are convenience wrappers — never required.

**Always confirm before restoring.** A restore overwrites existing data.
Never start a restore without typing the full word `yes` at the prompt,
even in non-interactive mode.

---

## Step 1: Assess First

```bash
# Is this a service crash (restart only) or actual data loss?
sudo systemctl status nginx mysql postgresql php8.3-fpm

# When did it happen?
sudo journalctl --since "2 hours ago" | grep -iE "error|fail|crash" | head -20
```

Service crash → restart it (`linux-service-management`), no restore needed.
Data loss/corruption → proceed below.

## Step 2: Find The Right Backup

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

Full restore procedure (decrypt → extract → import):
See `references/restore-procedures.md`.

The procedure, condensed:

```bash
# Decrypt (enter passphrase when prompted)
gpg --decrypt backup.sql.gz.gpg > backup.sql.gz

# Inspect size and sanity
gunzip -l backup.sql.gz
zcat backup.sql.gz | head -20

# Stop the service that writes to the DB
sudo systemctl stop nginx apache2 php8.3-fpm

# Restore (confirm first!)
zcat backup.sql.gz | mysql -u root -p <database>

# Restart
sudo systemctl start php8.3-fpm apache2 nginx
```

## Emergency Checklist

```bash
# 1. Stop affected service to prevent further damage
sudo systemctl stop <service>

# 2. Find best backup (Step 2 above)

# 3. Decrypt → restore → verify (references/restore-procedures.md)

# 4. Restart all services
sudo systemctl start nginx mysql php8.3-fpm apache2

# 5. Re-run security audit
sudo bash ~/.claude/skills/scripts/server-audit.sh

# 6. Clean up
rm -rf ~/restore/
```

## Demo/Dev Reset (Git-Tracked SQL Dump Pattern)

Some apps ship a git-tracked SQL dump as the demo DB source of truth.
A reset script drops and recreates from that dump:

```bash
ls /usr/local/bin/reset-*           # find available reset scripts
sudo reset-<app>-from-git           # requires typing YES
ls /var/backups/<app>/              # safety backup always created first
```

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-disaster-recovery` installs wrappers
for the above:

| Task | Fast-path script |
|---|---|
| Verify last backup is usable | `sudo sk-backup-verify` |
| Guided restore (pick backup, preview, confirm) | `sudo sk-restore-wizard` |
| MySQL restore from a specific file | `sudo sk-mysql-restore --file <path>` |
| PostgreSQL restore | `sudo sk-postgres-restore --file <path>` |
| Site file restore | `sudo sk-site-restore --backup <path> --target <dir>` |
| Maintenance mode on/off | `sudo sk-emergency-mode on\|off` |

These are optional wrappers around the commands above.

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
