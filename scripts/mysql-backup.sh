#!/usr/bin/env bash
#
# MySQL Backup Script
# - Dumps all databases individually + a combined all-databases dump
# - Compresses into a single timestamped .tar.gz
# - Uploads to Google Drive via rclone
# - Retains 7 days locally, 3 days on Google Drive
#
# Prerequisites:
#   - rclone configured with a Google Drive remote (see commands/rclone.md)
#   - MySQL credentials file (see notes/mysql-backup-setup.md)
#
# Usage:
#   ./mysql-backup.sh
#
# Cron (every 3 hours):
#   0 */3 * * * /home/administrator/mysql-backup.sh >> /home/administrator/backups/mysql/cron.log 2>&1

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────
MYSQL_CNF="$HOME/.mysql-backup.cnf"
BACKUP_DIR="$HOME/backups/mysql"
RCLONE_BIN="$HOME/.local/bin/rclone"          # adjust if installed elsewhere
RCLONE_REMOTE="gdrive:my-backup-folder"       # adjust remote name and folder
LOCAL_RETENTION_DAYS=7
REMOTE_RETENTION_DAYS=3
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
DUMP_DIR="$BACKUP_DIR/dump_${TIMESTAMP}"
ARCHIVE="$BACKUP_DIR/mysql-backup_${TIMESTAMP}.tar.gz"
LOGFILE="$BACKUP_DIR/backup.log"

# ── Functions ────────────────────────────────────────────────────────
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

cleanup_on_error() {
    log "ERROR: Backup failed. Cleaning up partial files."
    rm -rf "$DUMP_DIR" "$ARCHIVE" 2>/dev/null
}
trap cleanup_on_error ERR

# ── Pre-flight checks ───────────────────────────────────────────────
if [[ ! -f "$MYSQL_CNF" ]]; then
    log "FATAL: MySQL credentials file not found at $MYSQL_CNF"
    exit 1
fi

if [[ ! -x "$RCLONE_BIN" ]]; then
    log "FATAL: rclone not found at $RCLONE_BIN"
    exit 1
fi

mkdir -p "$BACKUP_DIR" "$DUMP_DIR"

# ── Step 1: Dump all databases individually ──────────────────────────
log "Starting MySQL backup..."

DATABASES=$(mysql --defaults-file="$MYSQL_CNF" -N -e \
    "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('information_schema','performance_schema','sys');" 2>/dev/null)

if [[ -z "$DATABASES" ]]; then
    log "FATAL: No databases found or cannot connect to MySQL."
    exit 1
fi

for DB in $DATABASES; do
    log "  Dumping database: $DB"
    mysqldump --defaults-file="$MYSQL_CNF" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --databases "$DB" > "$DUMP_DIR/${DB}.sql" 2>>"$LOGFILE"
done

# Full dump of everything (for easy full restore)
log "  Dumping all databases (combined)..."
mysqldump --defaults-file="$MYSQL_CNF" \
    --all-databases \
    --single-transaction \
    --routines \
    --triggers \
    --events > "$DUMP_DIR/all-databases.sql" 2>>"$LOGFILE"

# ── Step 2: Compress ────────────────────────────────────────────────
log "Compressing backup..."
tar -czf "$ARCHIVE" -C "$BACKUP_DIR" "dump_${TIMESTAMP}"
rm -rf "$DUMP_DIR"

ARCHIVE_SIZE=$(du -h "$ARCHIVE" | cut -f1)
log "Archive created: $ARCHIVE ($ARCHIVE_SIZE)"

# ── Step 3: Upload to Google Drive ──────────────────────────────────
log "Uploading to Google Drive ($RCLONE_REMOTE)..."
"$RCLONE_BIN" copy "$ARCHIVE" "$RCLONE_REMOTE" --log-level INFO 2>>"$LOGFILE"
log "Upload complete."

# ── Step 4: Local retention — delete backups older than 7 days ──────
log "Cleaning local backups older than $LOCAL_RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "mysql-backup_*.tar.gz" -type f -mtime +${LOCAL_RETENTION_DAYS} -delete -print 2>/dev/null | while read -r f; do
    log "  Deleted local: $f"
done

# ── Step 5: Remote retention — delete backups older than 3 days ─────
log "Cleaning remote backups older than $REMOTE_RETENTION_DAYS days..."
"$RCLONE_BIN" delete "$RCLONE_REMOTE" --min-age "${REMOTE_RETENTION_DAYS}d" --log-level INFO 2>>"$LOGFILE"
log "Remote cleanup complete."

log "Backup finished successfully."
