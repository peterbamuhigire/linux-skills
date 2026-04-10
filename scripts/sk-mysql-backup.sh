#!/usr/bin/env bash
#: Title:       sk-mysql-backup
#: Synopsis:    sk-mysql-backup [--yes] [--dry-run] [--log]
#: Description: Dump all MySQL databases (per-db + combined), compress to a
#:              timestamped tar.gz, GPG-encrypt with a passphrase file, upload
#:              to a configured rclone remote, and rotate both local and remote
#:              copies per retention policy. Interactive by default; --yes for
#:              cron invocations.
#: Author:      Peter Bamuhigire <techguypeter.com>
#: Contact:     +256784464178
#: Version:     0.2.0

# =============================================================================
# 1. Library + safety
# =============================================================================
set -uo pipefail

SK_LIB="/usr/local/lib/linux-skills/common.sh"
if [[ ! -f "$SK_LIB" ]]; then
    _SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SK_LIB="${_SD}/lib/common.sh"
fi
# shellcheck source=/dev/null
source "$SK_LIB" || { echo "FATAL: cannot source common.sh" >&2; exit 5; }

# =============================================================================
# 2. Defaults
# =============================================================================
SCRIPT_VERSION="0.2.0"

# These are overridable by a config file at /etc/linux-skills/mysql-backup.conf
# or by explicit flags. Never hard-code credentials here.
MYSQL_CNF="${MYSQL_CNF:-$HOME/.mysql-backup.cnf}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/mysql}"
GPG_KEY_FILE="${GPG_KEY_FILE:-$HOME/.backup-encryption-key}"
RCLONE_REMOTE="${RCLONE_REMOTE:-}"
LOCAL_RETENTION_DAYS="${LOCAL_RETENTION_DAYS:-7}"
REMOTE_RETENTION_DAYS="${REMOTE_RETENTION_DAYS:-3}"

CONFIG_FILE="/etc/linux-skills/mysql-backup.conf"

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-mysql-backup [OPTIONS]

Dump all MySQL databases, compress, GPG-encrypt, upload via rclone,
rotate local and remote copies. Designed for cron or interactive use.

CONFIG:
    Reads /etc/linux-skills/mysql-backup.conf if present. Overridable by
    environment variables or flags:
        MYSQL_CNF               MySQL credentials file (mode 600)
        BACKUP_DIR              Local backup directory
        GPG_KEY_FILE            Passphrase file for GPG symmetric encryption
        RCLONE_REMOTE           Rclone destination (e.g. gdrive:backups/host)
        LOCAL_RETENTION_DAYS    (default: 7)
        REMOTE_RETENTION_DAYS   (default: 3)

DECISION FLAGS (required under --yes if not in config):
    --mysql-cnf <path>
    --backup-dir <path>
    --gpg-key-file <path>
    --rclone-remote <remote:path>

STANDARD FLAGS:
    -h, --help              Show this help and exit
        --version           Print version
    -y, --yes               Non-interactive mode (for cron)
    -n, --dry-run           Print actions, change nothing
        --log               Tee output to /var/log/linux-skills/
    -v, --verbose           Extra diagnostic output
    -q, --quiet             Errors and result only

EXIT CODES:
    0  success
    1  backup failed
    2  usage/flag error
    3  precondition failed
    5  dependency missing (rclone, gpg, mysqldump)

EXAMPLES:
    sudo sk-mysql-backup                          # interactive
    sudo sk-mysql-backup --yes --log              # for cron
    sudo sk-mysql-backup --dry-run                # preview

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        info "loaded config from $CONFIG_FILE"
    fi
}

cleanup_dump() {
    [[ -n "${DUMP_DIR:-}" ]] && rm -rf "$DUMP_DIR" 2>/dev/null || true
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
parse_standard_flags "$@"

while (( ${#REMAINING_ARGS[@]} > 0 )); do
    case "${REMAINING_ARGS[0]}" in
        --mysql-cnf)
            MYSQL_CNF="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --backup-dir)
            BACKUP_DIR="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --gpg-key-file)
            GPG_KEY_FILE="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --rclone-remote)
            RCLONE_REMOTE="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        *)
            die "unknown argument: ${REMAINING_ARGS[0]}" 2
            ;;
    esac
done

# =============================================================================
# 5. Sanity checks
# =============================================================================
load_config
require_debian
require_cmd mysqldump gpg tar find

[[ -n "$RCLONE_REMOTE" ]] && require_cmd rclone

[[ -f "$MYSQL_CNF" ]] || die "MySQL credentials file not found: $MYSQL_CNF" 3
[[ -f "$GPG_KEY_FILE" ]] || die "GPG key file not found: $GPG_KEY_FILE" 3

# Verify permissions on credential files
for f in "$MYSQL_CNF" "$GPG_KEY_FILE"; do
    mode=$(stat -c '%a' "$f")
    if [[ "$mode" != "600" ]]; then
        fail "$f has mode $mode, must be 600"
        die "credential file permissions" 3
    fi
done

if [[ "$YES" == "1" ]]; then
    require_flag RCLONE_REMOTE
fi

# =============================================================================
# 6. Main logic
# =============================================================================

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
DUMP_DIR="$BACKUP_DIR/dump_$TIMESTAMP"
ARCHIVE="$BACKUP_DIR/mysql-backup_$TIMESTAMP.tar.gz"
ENCRYPTED="$ARCHIVE.gpg"

sk_on_exit cleanup_dump

header "sk-mysql-backup — $(hostname)"
info "timestamp:    $TIMESTAMP"
info "backup dir:   $BACKUP_DIR"
info "rclone:       ${RCLONE_REMOTE:-<not configured>}"
info "local keep:   $LOCAL_RETENTION_DAYS days"
info "remote keep:  $REMOTE_RETENTION_DAYS days"

if ! confirm "Proceed with backup?" Y; then
    die "user aborted" 4
fi

# --- Step 1: Ensure dirs -----------------------------------------------------
run mkdir -p "$BACKUP_DIR" "$DUMP_DIR"

# --- Step 2: Enumerate databases ---------------------------------------------
header "Step 1/5: Enumerating databases"
DATABASES=$(mysql --defaults-file="$MYSQL_CNF" -N -e \
    "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('information_schema','performance_schema','sys');" 2>/dev/null) \
    || die "cannot connect to MySQL" 1

if [[ -z "$DATABASES" ]]; then
    die "no databases found" 1
fi

DB_COUNT=$(echo "$DATABASES" | wc -l)
info "$DB_COUNT databases to back up"

# --- Step 3: Dump ------------------------------------------------------------
header "Step 2/5: Dumping databases"
for DB in $DATABASES; do
    info "  dumping $DB"
    if [[ "$DRY_RUN" == "1" ]]; then
        info "  (dry-run skipped)"
    else
        mysqldump --defaults-file="$MYSQL_CNF" \
            --single-transaction --routines --triggers --events \
            --databases "$DB" > "$DUMP_DIR/${DB}.sql" \
            || die "mysqldump failed for $DB" 1
    fi
done

if [[ "$DRY_RUN" != "1" ]]; then
    info "  dumping all-databases (combined)"
    mysqldump --defaults-file="$MYSQL_CNF" \
        --all-databases --single-transaction --routines --triggers --events \
        > "$DUMP_DIR/all-databases.sql" \
        || die "mysqldump --all-databases failed" 1
fi

pass "dumps complete"

# --- Step 4: Compress --------------------------------------------------------
header "Step 3/5: Compressing"
if [[ "$DRY_RUN" == "1" ]]; then
    info "DRY-RUN would create $ARCHIVE"
else
    tar -czf "$ARCHIVE" -C "$BACKUP_DIR" "dump_$TIMESTAMP" \
        || die "tar compression failed" 1
    rm -rf "$DUMP_DIR"
    SIZE=$(du -h "$ARCHIVE" | cut -f1)
    pass "archive: $ARCHIVE ($SIZE)"
fi

# --- Step 5: Encrypt ---------------------------------------------------------
header "Step 4/5: Encrypting with GPG"
if [[ "$DRY_RUN" == "1" ]]; then
    info "DRY-RUN would encrypt to $ENCRYPTED"
else
    gpg --batch --symmetric --cipher-algo AES256 \
        --passphrase-file "$GPG_KEY_FILE" \
        -o "$ENCRYPTED" "$ARCHIVE" \
        || die "gpg encryption failed" 1
    rm -f "$ARCHIVE"
    pass "encrypted: $ENCRYPTED"
    _sk_audit "encrypted backup $ENCRYPTED"
fi

# --- Step 6: Upload ----------------------------------------------------------
header "Step 5/5: Uploading to remote"
if [[ -z "$RCLONE_REMOTE" ]]; then
    info "no rclone remote configured, skipping upload"
elif [[ "$DRY_RUN" == "1" ]]; then
    info "DRY-RUN would upload to $RCLONE_REMOTE"
else
    run rclone copy "$ENCRYPTED" "$RCLONE_REMOTE/" --log-level INFO \
        || die "rclone upload failed" 1
    pass "uploaded to $RCLONE_REMOTE"
    _sk_audit "uploaded backup to $RCLONE_REMOTE"
fi

# --- Rotation ----------------------------------------------------------------
header "Rotation: pruning old copies"
if [[ "$DRY_RUN" == "1" ]]; then
    info "DRY-RUN would prune local > $LOCAL_RETENTION_DAYS days, remote > $REMOTE_RETENTION_DAYS days"
else
    find "$BACKUP_DIR" -name '*.gpg' -type f -mtime "+${LOCAL_RETENTION_DAYS}" -delete -print 2>/dev/null \
        | while read -r f; do info "  pruned local: $f"; done

    if [[ -n "$RCLONE_REMOTE" ]]; then
        run rclone delete "$RCLONE_REMOTE/" \
            --min-age "${REMOTE_RETENTION_DAYS}d" \
            --include '*.gpg' \
            2>&1 | grep -v "^$" || true
    fi
fi

print_summary
pass "backup completed successfully"
exit 0
