# MySQL Backup to Google Drive - Complete Setup Guide

Step-by-step guide for setting up automated MySQL backups with rclone upload to Google Drive.

## Prerequisites

- MySQL/MariaDB installed and running
- rclone installed and configured with Google Drive (see `commands/rclone.md`)

## Step 1: Create MySQL Credentials File

Create `~/.mysql-backup.cnf` so the script can connect without passwords in the command line:

```bash
cat > ~/.mysql-backup.cnf << 'EOF'
[client]
user=root
password=YOUR_MYSQL_ROOT_PASSWORD

[mysqldump]
user=root
password=YOUR_MYSQL_ROOT_PASSWORD
EOF

chmod 600 ~/.mysql-backup.cnf
```

Test it:
```bash
mysql --defaults-file=~/.mysql-backup.cnf -e "SHOW DATABASES;"
```

## Step 2: Create Backup Directory

```bash
mkdir -p ~/backups/mysql
```

## Step 3: Install the Backup Script

Copy `scripts/mysql-backup.sh` to your home directory:

```bash
cp ~/linux-skills/scripts/mysql-backup.sh ~/mysql-backup.sh
chmod +x ~/mysql-backup.sh
```

Edit the configuration section at the top:

```bash
RCLONE_BIN="$HOME/.local/bin/rclone"          # path to rclone binary
RCLONE_REMOTE="gdrive:my-backup-folder"       # remote:folder
```

## Step 4: Create the Google Drive Folder

```bash
rclone mkdir gdrive:my-backup-folder
```

## Step 5: Test the Backup

```bash
./mysql-backup.sh
```

Verify:
```bash
# Check local backup
ls -lh ~/backups/mysql/mysql-backup_*.tar.gz

# Check Google Drive
rclone ls gdrive:my-backup-folder
```

## Step 6: Set Up Cron

```bash
crontab -e
```

Add (every 3 hours):
```cron
# MySQL backup every 3 hours
0 */3 * * * /home/administrator/mysql-backup.sh >> /home/administrator/backups/mysql/cron.log 2>&1
```

Common schedules:
```cron
0 */3 * * *    # Every 3 hours: 00, 03, 06, 09, 12, 15, 18, 21
0 */4 * * *    # Every 4 hours: 00, 04, 08, 12, 16, 20
0 */6 * * *    # Every 6 hours: 00, 06, 12, 18
0 2 * * *      # Daily at 2 AM
```

**Note:** Cron uses the server's timezone. Check with `timedatectl`. To set timezone:
```bash
sudo timedatectl set-timezone Africa/Nairobi   # EAT (UTC+3)
```

## Retention Policy

| Location | Retention | Controlled By |
|----------|-----------|---------------|
| Local | 7 days | `find -mtime +7 -delete` |
| Google Drive | 3 days | `rclone delete --min-age 3d` |

Adjust `LOCAL_RETENTION_DAYS` and `REMOTE_RETENTION_DAYS` in the script.

## What Gets Backed Up

- Each database is dumped individually (`database_name.sql`)
- A combined `all-databases.sql` dump for easy full restore
- System databases (`information_schema`, `performance_schema`, `sys`) are excluded
- Everything compressed into a single `mysql-backup_TIMESTAMP.tar.gz`

## Restoring from Backup

### Restore a single database:
```bash
tar xzf mysql-backup_2026-02-15_09-13-07.tar.gz
mysql --defaults-file=~/.mysql-backup.cnf < dump_2026-02-15_09-13-07/mydb.sql
```

### Restore all databases:
```bash
tar xzf mysql-backup_2026-02-15_09-13-07.tar.gz
mysql --defaults-file=~/.mysql-backup.cnf < dump_2026-02-15_09-13-07/all-databases.sql
```

### Restore from Google Drive:
```bash
rclone copy gdrive:my-backup-folder/mysql-backup_2026-02-15_09-13-07.tar.gz ~/restore/
tar xzf ~/restore/mysql-backup_2026-02-15_09-13-07.tar.gz -C ~/restore/
```

## Monitoring

Check the log:
```bash
tail -50 ~/backups/mysql/backup.log
```

Check cron output:
```bash
tail -50 ~/backups/mysql/cron.log
```

## Troubleshooting

- **"FATAL: MySQL credentials file not found"** — create `~/.mysql-backup.cnf` (see Step 1)
- **"FATAL: rclone not found"** — check `RCLONE_BIN` path in script, or run `which rclone`
- **"FATAL: No databases found"** — test MySQL connection with `mysql --defaults-file=~/.mysql-backup.cnf -e "SHOW DATABASES;"`
- **Upload fails** — test rclone with `rclone about gdrive:`, may need to reconnect
- **Cron not running** — check with `crontab -l`, check logs in `/var/log/syslog` or `journalctl -u cron`
