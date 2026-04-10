# Restore procedures

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This file is the complete restore reference for an Ubuntu/Debian server
running Nginx + PHP-FPM + MySQL + PostgreSQL + Redis, with GPG-encrypted
backups rotated locally and to Google Drive via `rclone`. Every procedure
is written to work on a stock server with no `sk-*` scripts installed.

**Read before acting.** A restore overwrites data. Work from a copy, not
the original. Never skip the verification step at the end of each procedure.

## Table of contents

- [Pre-restore checklist](#pre-restore-checklist)
- [MySQL single-database restore](#mysql-single-database-restore)
- [MySQL full-server restore](#mysql-full-server-restore)
- [MySQL point-in-time recovery](#mysql-point-in-time-recovery)
- [PostgreSQL restore](#postgresql-restore)
- [Redis restore](#redis-restore)
- [Site files restore](#site-files-restore)
- [/etc restore from config snapshot](#etc-restore-from-config-snapshot)
- [Cold restore — whole server gone](#cold-restore--whole-server-gone)
- [Dry-run restore in an LXD container](#dry-run-restore-in-an-lxd-container)
- [Demo/dev reset pattern](#demodev-reset-pattern)
- [Post-restore verification](#post-restore-verification)
- [Cleanup](#cleanup)
- [Sources](#sources)

---

## Pre-restore checklist

Before touching anything:

1. **Is this a restore or a restart?** Check `systemctl status` first. A
   service crash is not a data loss event — restart it and investigate why.
2. **How old is the most recent good backup?** List local and remote:
   ```bash
   ls -lth ~/backups/mysql/*.gpg 2>/dev/null | head -5
   rclone ls gdrive:<backup-folder> 2>/dev/null | sort | tail -5
   ```
3. **Do you have the GPG passphrase and the backup key file?**
   ```bash
   ls -la ~/.backup-encryption-key    # must be mode 600
   ```
4. **Is there enough disk space to stage the restore?** A restore needs
   roughly 2-3× the backup size free.
5. **Communicate.** Tell stakeholders before starting. A restore is visible.
6. **Stop writes** to whatever you're restoring. You don't want new writes
   fighting the restore:
   ```bash
   sudo systemctl stop nginx apache2 php8.3-fpm
   ```
7. **Decide the rollback point.** If the restore fails, what do you revert
   to? Take a fresh snapshot *before* restoring:
   ```bash
   sudo mysqldump --all-databases > /tmp/pre-restore-$(date +%Y%m%d-%H%M).sql
   sudo tar czf /tmp/pre-restore-www-$(date +%Y%m%d-%H%M).tar.gz /var/www/html
   ```

Only then proceed.

---

## MySQL single-database restore

### Step 1: Stage the backup file

```bash
mkdir -p ~/restore && cd ~/restore

# From Google Drive
rclone ls gdrive:<backup-folder> | sort | tail -10
rclone copy gdrive:<backup-folder>/mysql-backup_20260410-0200.tar.gz.gpg .

# Or from local retention
cp ~/backups/mysql/mysql-backup_20260410-0200.tar.gz.gpg ./
```

### Step 2: Decrypt

```bash
gpg --batch \
    --passphrase-file ~/.backup-encryption-key \
    -d mysql-backup_20260410-0200.tar.gz.gpg \
    > mysql-backup_20260410-0200.tar.gz

# Verify size looks sensible (not zero, not corrupt):
ls -lh mysql-backup_20260410-0200.tar.gz
```

If decrypt fails:
```bash
cat ~/.backup-encryption-key    # not empty?
ls -la ~/.backup-encryption-key # mode 600?
file mysql-backup_20260410-0200.tar.gz.gpg   # "GPG symmetrically encrypted data"
```

### Step 3: Extract and inspect

```bash
tar tzf mysql-backup_20260410-0200.tar.gz | head -20       # peek at contents
tar xzf mysql-backup_20260410-0200.tar.gz
ls dump_*/                                                 # shows db files
head -30 dump_20260410-0200/<db-name>.sql                  # sanity check
```

### Step 4: Create a scratch database (optional safety)

To verify the restore works *before* overwriting production:

```bash
mysql -u root -p -e "CREATE DATABASE IF NOT EXISTS <db>_restore_scratch;"
mysql -u root -p <db>_restore_scratch < dump_20260410-0200/<db-name>.sql
mysql -e "USE <db>_restore_scratch; SHOW TABLES; SELECT COUNT(*) FROM <biggest-table>;"
```

If the scratch restore looks correct, proceed. If not, stop — the backup is
corrupt or from the wrong window.

### Step 5: Restore into production

```bash
# Confirm (type 'yes' to yourself)
echo "Restoring <db-name> from backup dated 2026-04-10 02:00. Continue? [type yes]"
read ANS && [[ "$ANS" == "yes" ]] || exit 1

# Stop writers
sudo systemctl stop nginx apache2 php8.3-fpm

# Restore (this overwrites the current <db>)
mysql -u root -p <db-name> < dump_20260410-0200/<db-name>.sql

# Restart writers
sudo systemctl start php8.3-fpm apache2 nginx
```

### Step 6: Verify (see [Post-restore verification](#post-restore-verification))

---

## MySQL full-server restore

Use when multiple databases are corrupted or you're rebuilding on a new
server.

### Extract the backup

```bash
# Same decrypt/extract as single-database.
# Look for an all-databases.sql or per-db SQL files:
ls dump_20260410-0200/
```

### Stop MySQL writers

```bash
sudo systemctl stop nginx apache2 php8.3-fpm
```

### Restore

If the backup is a single `all-databases.sql`:

```bash
mysql -u root -p < dump_20260410-0200/all-databases.sql
```

If it's per-database dumps:

```bash
for f in dump_20260410-0200/*.sql; do
    db=$(basename "$f" .sql)
    echo "Restoring $db..."
    mysql -u root -p "$db" < "$f" || { echo "FAILED on $db"; break; }
done
```

### Restore users and grants (if stored separately)

`mysqldump` with `--all-databases` covers users, but `mysqldump`
per-database does not. If your backup is per-db only, you also need:

```bash
# Backup time (you should already have this)
mysqldump -u root -p --all-databases --events --routines --triggers \
    > all-with-grants.sql

# Restore time
mysql -u root -p < all-with-grants.sql
```

### Re-run privilege refresh

```bash
mysql -e "FLUSH PRIVILEGES;"
```

### Restart writers and verify

```bash
sudo systemctl start php8.3-fpm apache2 nginx
mysql -e "SHOW DATABASES;"
```

---

## MySQL point-in-time recovery

Use when you need to restore to a moment between backups (e.g. an accidental
`DELETE` at 14:32 and the last backup was at 02:00).

**Requires** MySQL binary logging enabled (`log_bin` in `mysqld.cnf`) and
binlogs preserved since the last full backup.

### Step 1: Restore the full backup as usual

(See [MySQL full-server restore](#mysql-full-server-restore).)

### Step 2: Identify the binlog window to replay

```bash
# List available binlogs
sudo ls -lh /var/lib/mysql/mysql-bin.*

# The backup job should record the binlog position it started at.
# If not, find it by timestamp:
sudo mysqlbinlog --start-datetime="2026-04-10 02:00:00" \
                 --stop-datetime="2026-04-10 14:31:59" \
                 /var/lib/mysql/mysql-bin.000042 | head -50
```

### Step 3: Replay the binlog, stopping before the bad event

```bash
sudo mysqlbinlog --start-datetime="2026-04-10 02:00:00" \
                 --stop-datetime="2026-04-10 14:31:59" \
                 /var/lib/mysql/mysql-bin.000042 \
                 /var/lib/mysql/mysql-bin.000043 \
    | mysql -u root -p
```

If you can identify the bad event by position (clearer than timestamp):

```bash
# Use --stop-position=<exact-byte> from the bad event
sudo mysqlbinlog --stop-position=12345678 /var/lib/mysql/mysql-bin.000043 \
    | mysql -u root -p
```

### Step 4: Verify the restored row(s) are back; check nothing after the bad event is duplicated.

---

## PostgreSQL restore

### From a `pg_dump` plain SQL backup

```bash
# Decrypt and extract as usual
gpg --batch --passphrase-file ~/.backup-encryption-key \
    -d ~/restore/pg-backup_20260410-0200.sql.gz.gpg \
    | gunzip > ~/restore/pg-backup_20260410-0200.sql

# Stop writers
sudo systemctl stop nginx apache2 php8.3-fpm

# Restore (this runs as postgres)
sudo -u postgres psql -f ~/restore/pg-backup_20260410-0200.sql postgres

# Or into a specific database (if the dump was single-db):
sudo -u postgres psql <dbname> -f ~/restore/pg-backup_20260410-0200.sql
```

### From a `pg_dump -Fc` custom-format backup

```bash
# Decrypt into a .dump file
gpg --batch --passphrase-file ~/.backup-encryption-key \
    -d ~/restore/pg-backup_20260410-0200.dump.gpg \
    > ~/restore/pg-backup_20260410-0200.dump

# Restore (jobs parallelises)
sudo -u postgres pg_restore -d <dbname> -j 4 \
    --verbose ~/restore/pg-backup_20260410-0200.dump
```

### Restart and verify

```bash
sudo systemctl restart postgresql
sudo -u postgres psql -c "\l"
sudo -u postgres psql <dbname> -c "\dt"
sudo -u postgres psql <dbname> -c "SELECT COUNT(*) FROM <biggest-table>;"
```

---

## Redis restore

Redis persists via RDB snapshots (`/var/lib/redis/dump.rdb`) and optionally
AOF (`/var/lib/redis/appendonly.aof`). Restore = replace the files and
restart.

```bash
# Stop Redis
sudo systemctl stop redis-server

# Back up the current state just in case
sudo cp /var/lib/redis/dump.rdb /tmp/dump.rdb.broken
sudo cp /var/lib/redis/appendonly.aof /tmp/appendonly.aof.broken 2>/dev/null

# Install the restored file
sudo cp ~/restore/dump.rdb /var/lib/redis/dump.rdb
sudo chown redis:redis /var/lib/redis/dump.rdb
sudo chmod 660 /var/lib/redis/dump.rdb

# Start
sudo systemctl start redis-server
sudo systemctl status redis-server --no-pager

# Verify
redis-cli ping            # PONG
redis-cli DBSIZE          # number of keys
```

Redis sessions are usually ephemeral — consider whether you actually need
to restore, or just let the app rebuild them.

---

## Site files restore

### Extract the site archive

```bash
gpg --batch --passphrase-file ~/.backup-encryption-key \
    -d ~/restore/site-<name>_20260410-0200.tar.gz.gpg \
    > ~/restore/site-<name>.tar.gz

mkdir -p ~/restore/site-<name>
tar xzf ~/restore/site-<name>.tar.gz -C ~/restore/site-<name>/
```

### Rsync into place (safer than overwriting the full tree)

```bash
# Stop writers
sudo systemctl stop nginx apache2 php8.3-fpm

# Take a safety snapshot of the current state
sudo tar czf /tmp/current-site-<name>-$(date +%Y%m%d-%H%M).tar.gz \
    /var/www/html/<name>/

# Rsync the restored files in
sudo rsync -av --delete \
    ~/restore/site-<name>/var/www/html/<name>/ \
    /var/www/html/<name>/

# Fix ownership and permissions
sudo chown -R www-data:www-data /var/www/html/<name>/
sudo find /var/www/html/<name> -type d -exec chmod 755 {} \;
sudo find /var/www/html/<name> -type f -exec chmod 644 {} \;
sudo find /var/www/html/<name> -type f -perm -0002 -exec chmod o-w {} \;

# Restart
sudo systemctl start php8.3-fpm apache2 nginx
```

### Astro / Node sites

If the archive contained `node_modules`, delete it and rebuild — it's
quicker and safer than trusting archived deps:

```bash
cd /var/www/html/<name>
sudo rm -rf node_modules dist
sudo npm install --production
sudo npm run build
```

### PHP / Composer sites

```bash
cd /var/www/html/<name>
sudo -u www-data composer install --no-dev --optimize-autoloader
```

---

## /etc restore from config snapshot

If `/etc/` was tracked in git (etckeeper) or backed up via `sk-config-snapshot`.

### From etckeeper

```bash
# Show recent commits
sudo etckeeper vcs log --oneline | head -20

# Show what changed between two points
sudo etckeeper vcs diff HEAD~5..HEAD -- ssh/sshd_config

# Restore a specific file to an earlier commit
sudo etckeeper vcs checkout <commit-hash> -- ssh/sshd_config

# Full rollback of all /etc
sudo etckeeper vcs reset --hard <commit-hash>

# Apply and verify
sudo sshd -t              # if you changed sshd_config
sudo systemctl restart ssh
```

### From a tar snapshot

```bash
# Decrypt and extract to a staging area — NEVER directly into /etc
mkdir -p ~/restore/etc-stage
gpg --batch --passphrase-file ~/.backup-encryption-key \
    -d ~/restore/etc-snapshot_20260410.tar.gz.gpg \
    | tar xz -C ~/restore/etc-stage/

# Inspect what's different from live
sudo diff -rq /etc/ ~/restore/etc-stage/etc/ | head -30

# Cherry-pick individual files with cp after comparing
sudo cp ~/restore/etc-stage/etc/nginx/sites-available/example.conf \
    /etc/nginx/sites-available/example.conf

# Validate and reload
sudo nginx -t && sudo systemctl reload nginx
```

**Do not** blanket-replace `/etc/` with an archive. You'll clobber
machine-specific files (cloud-init identity, netplan, fstab UUIDs) and
brick the boot.

---

## Cold restore — whole server gone

The server is destroyed. You have only the backups.

### Prerequisites

- Cloud-init user-data for the original server (or `sk-provision-fresh`
  wizard) saved somewhere.
- Backups accessible via rclone from a different machine.
- DNS or reverse-proxy control to point traffic at the new server.
- A GPG key file (`.backup-encryption-key`) stored safely off-server.

### Steps

1. **Launch a fresh Ubuntu/Debian VM** at the same or different provider.
2. **Run cloud-init user-data** to bootstrap hostname, admin user, SSH key,
   UFW baseline, linux-skills clone.
3. **Run `sk-provision-fresh`** (or manual `linux-server-provisioning`
   sections) to install the web stack, databases, fail2ban, certbot.
4. **Install rclone and reconnect the backup remote**:
   ```bash
   sudo apt install rclone
   rclone config
   rclone config reconnect gdrive:
   ```
5. **Copy the GPG key** (`.backup-encryption-key`) onto the new server,
   `chmod 600` it.
6. **Download the most recent backups** (MySQL, sites, /etc snapshot).
7. **Restore MySQL** (full-server procedure above).
8. **Restore site files** (site restore procedure above).
9. **Restore nginx vhosts** (cherry-pick from /etc snapshot).
10. **Issue new certificates** — the old ones were on the old server:
    ```bash
    sudo certbot --nginx -d <each-domain>
    ```
11. **Register each restored repo in `update-all-repos`**.
12. **Point DNS at the new IP** (or update load balancer).
13. **Run `sk-audit`** (or `sudo bash ~/.claude/skills/scripts/server-audit.sh`).
14. **Document the incident** in the backup strategy file.

Budget: 2-4 hours for a single-server web stack, assuming backups are
recent and DNS TTL is short.

---

## Dry-run restore in an LXD container

You don't have a backup if you haven't restored from it. Do a dry-run
restore every quarter in a disposable LXD container.

```bash
# Launch a disposable container
lxc launch ubuntu:24.04 restore-test
lxc exec restore-test -- apt update
lxc exec restore-test -- apt install -y mysql-server gpg rclone

# Push the backup in
lxc file push ~/backups/mysql/mysql-backup_20260410-0200.tar.gz.gpg \
    restore-test/root/
lxc file push ~/.backup-encryption-key restore-test/root/

# Run the restore inside the container
lxc exec restore-test -- bash -c '
  chmod 600 /root/.backup-encryption-key
  gpg --batch --passphrase-file /root/.backup-encryption-key \
      -d /root/mysql-backup_20260410-0200.tar.gz.gpg | tar xz -C /root/
  for f in /root/dump_*/*.sql; do
      db=$(basename "$f" .sql)
      mysql -e "CREATE DATABASE IF NOT EXISTS $db;"
      mysql "$db" < "$f"
  done
  mysql -e "SHOW DATABASES;"
'

# Clean up
lxc delete restore-test --force
```

If the container restore works, your real backup works. If not, you have a
backup problem to fix *before* the incident.

---

## Demo/dev reset pattern

Some apps ship a git-tracked SQL dump as the canonical demo database. A
reset script drops and recreates from that dump for testing or training.

```bash
# List available reset scripts
ls /usr/local/bin/reset-*

# Run the reset (requires typing YES)
sudo reset-<app>-from-git

# The script should always make a safety backup first
ls /var/backups/<app>/
```

This is NOT the same as a real restore — use only on staging/demo
environments.

---

## Post-restore verification

Run every single check after any restore before declaring success.

```bash
# Services up
for s in nginx apache2 mysql postgresql php8.3-fpm redis-server fail2ban; do
    printf "%-20s %s\n" $s "$(sudo systemctl is-active $s)"
done

# HTTP responds on each domain
for d in example.com other.example.com; do
    curl -sI "https://$d" | head -1
done

# Database row counts match expectation
mysql -e "SELECT table_schema, COUNT(*) FROM information_schema.tables GROUP BY table_schema;"

# Key application table has the expected record count
mysql -e "SELECT COUNT(*) FROM <db>.<table>;"

# Recent log is clean (no fresh error spam)
sudo tail -50 /var/log/nginx/error.log
sudo tail -50 /var/log/php8.3-fpm.log
sudo journalctl -u mysql --since "5 min ago" --no-pager

# Backup is still running — don't let the incident break tomorrow's backup
sudo systemctl list-timers | grep -i backup
crontab -l | grep -i backup
```

### The 24-hour observation window

A successful restore is one that's still working 24 hours later. Schedule
a check:

```bash
at now + 1 hour <<'EOF'
echo "Post-restore 1h check: $(date)" >> /var/log/restore-observation.log
systemctl is-active nginx mysql php8.3-fpm >> /var/log/restore-observation.log
EOF
```

---

## Cleanup

Only after the 24-hour observation window confirms the restore is stable:

```bash
rm -rf ~/restore/
rm -rf /tmp/app-restore/
rm /tmp/pre-restore-*.sql /tmp/pre-restore-www-*.tar.gz

# Do NOT delete the original .gpg archive yet — keep it for another cycle
# in case a subtle corruption surfaces later.
```

Update the backup strategy document with any lessons learned.

---

## Sources

- Book: *Linux System Administration for the 2020s* — incident recovery
  and "you don't have a backup until you've restored from it" philosophy.
- Book: *Mastering Ubuntu* (Atef, 2023) — MySQL and PostgreSQL backup and
  restore chapters.
- Book: *Ubuntu Server Guide* (Canonical) — `pg_dump` / `pg_restore`
  reference.
- MySQL 8 reference manual: binary log based point-in-time recovery.
- Man pages: `mysqldump(1)`, `mysql(1)`, `mysqlbinlog(1)`, `pg_dump(1)`,
  `pg_restore(1)`, `rsync(1)`, `gpg(1)`, `rclone(1)`.
