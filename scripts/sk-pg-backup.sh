#!/usr/bin/env bash
#: Title:       sk-pg-backup
#: Synopsis:    sk-pg-backup [--db NAME|--all] [--backup-dir DIR] [--yes] [--dry-run]
#: Description: Logical backup of PostgreSQL. Dumps one database (--db) or every
#:              database (--all, default) with pg_dump --format=custom to a
#:              timestamped file, plus pg_dumpall --globals-only to capture roles
#:              and tablespaces. Compressed custom format is restorable with
#:              pg_restore (selective/parallel). Optional WAL-archive sanity check.
#:              Read-only against the database: it dumps, never drops or modifies
#:              data. Interactive by default; --yes for cron. Both families.
#: Author:      Peter Bamuhigire <techguypeter.com>
#: Contact:     +256784464178
#: Version:     0.1.0

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
SCRIPT_VERSION="0.1.0"

# Run dumps as the postgres OS user (peer auth) unless overridden.
PG_USER="${PG_USER:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/postgresql}"
TARGET_DB="${TARGET_DB:-}"        # empty + ALL_DBS=1 means dump every database
ALL_DBS=1
RETENTION_DAYS="${RETENTION_DAYS:-7}"
WAL_ARCHIVE_DIR="${WAL_ARCHIVE_DIR:-}"   # if set, sanity-check it is non-empty

CONFIG_FILE="/etc/linux-skills/pg-backup.conf"

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-pg-backup [OPTIONS]

Logical PostgreSQL backup using pg_dump --format=custom (one or all databases)
plus pg_dumpall --globals-only for roles/tablespaces. Timestamped, compressed,
rotated by retention. Read-only against the database — never drops or modifies
data. Interactive by default; --yes for cron.

CONFIG:
    Reads /etc/linux-skills/pg-backup.conf if present. Overridable by
    environment variables or flags:
        PG_USER             OS user to run dumps as (peer auth; default: postgres)
        BACKUP_DIR          Local backup directory (default: /var/backups/postgresql)
        RETENTION_DAYS      Prune dumps older than this many days (default: 7)
        WAL_ARCHIVE_DIR     If set, verify the WAL archive dir is non-empty

DECISION FLAGS:
        --db <name>         Back up only this database
        --all               Back up every database (default)
        --backup-dir <dir>  Override backup directory
        --pg-user <user>    Override OS user (peer auth)
        --retention <days>  Override retention days
        --wal-archive <dir> Sanity-check this WAL archive directory

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
    5  dependency missing (pg_dump / pg_dumpall / psql)

EXAMPLES:
    sudo sk-pg-backup                         # interactive, all databases
    sudo sk-pg-backup --db appdb              # single database
    sudo sk-pg-backup --all --yes --log       # for cron
    sudo sk-pg-backup --dry-run               # preview, change nothing

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

# Ask before overwriting an existing target. Returns 0 to proceed (write),
# 1 to skip. A non-existent file always proceeds. Under --yes, confirm()
# auto-proceeds. In --dry-run nothing is written, so always "proceed" (the
# write step itself is a no-op under DRY_RUN).
ask_overwrite() {
    local f="$1"
    [[ ! -e "$f" ]] && return 0
    [[ "$DRY_RUN" == "1" ]] && return 0
    confirm "Overwrite existing $f?" N
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
parse_standard_flags "$@"

while (( ${#REMAINING_ARGS[@]} > 0 )); do
    case "${REMAINING_ARGS[0]}" in
        --db)
            TARGET_DB="${REMAINING_ARGS[1]:-}"
            ALL_DBS=0
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --all)
            ALL_DBS=1
            TARGET_DB=""
            REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
            ;;
        --backup-dir)
            BACKUP_DIR="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --pg-user)
            PG_USER="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --retention)
            RETENTION_DAYS="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --wal-archive)
            WAL_ARCHIVE_DIR="${REMAINING_ARGS[1]:-}"
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
require_family any        # runs on Debian/Ubuntu and the RHEL family
require_cmd pg_dump pg_dumpall psql

if [[ "$ALL_DBS" == "0" ]]; then
    require_flag TARGET_DB
fi

# =============================================================================
# 6. Main logic
# =============================================================================

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
GLOBALS_FILE="$BACKUP_DIR/globals_$TIMESTAMP.sql"

header "sk-pg-backup — $(hostname)"
info "timestamp:    $TIMESTAMP"
info "pg user:      $PG_USER (peer auth)"
info "backup dir:   $BACKUP_DIR"
if [[ "$ALL_DBS" == "1" ]]; then
    info "scope:        all databases"
else
    info "scope:        database '$TARGET_DB'"
fi
info "retention:    $RETENTION_DAYS days"
info "wal check:    ${WAL_ARCHIVE_DIR:-<disabled>}"

if ! confirm "Proceed with backup?" Y; then
    die "user aborted" 4
fi

# --- Step 1: Ensure backup dir ----------------------------------------------
run mkdir -p "$BACKUP_DIR"

# --- Step 2: Enumerate databases --------------------------------------------
header "Step 1/4: Enumerating databases"
if [[ "$ALL_DBS" == "1" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
        info "DRY-RUN: would list databases via psql"
        DATABASES=""
    else
        DATABASES=$(sudo -u "$PG_USER" psql -At -c \
            "SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres';" 2>/dev/null) \
            || die "cannot connect to PostgreSQL as $PG_USER" 1
        if [[ -z "$DATABASES" ]]; then
            die "no user databases found" 1
        fi
        info "$(echo "$DATABASES" | wc -l) database(s) to back up"
    fi
else
    DATABASES="$TARGET_DB"
fi

# --- Step 3: Dump globals (roles, tablespaces) ------------------------------
header "Step 2/4: Dumping globals (roles, tablespaces)"
if ask_overwrite "$GLOBALS_FILE"; then
    if [[ "$DRY_RUN" == "1" ]]; then
        info "DRY-RUN: would write $GLOBALS_FILE"
    else
        sudo -u "$PG_USER" pg_dumpall --globals-only > "$GLOBALS_FILE" \
            || die "pg_dumpall --globals-only failed" 1
        pass "globals: $GLOBALS_FILE"
    fi
else
    info "skipped globals (file exists, not overwritten)"
fi

# --- Step 4: Dump each database (custom format) -----------------------------
header "Step 3/4: Dumping databases (pg_dump --format=custom)"
for DB in $DATABASES; do
    DUMP_FILE="$BACKUP_DIR/${DB}_$TIMESTAMP.dump"
    info "  dumping $DB -> $DUMP_FILE"
    if ! ask_overwrite "$DUMP_FILE"; then
        info "  skipped $DB (file exists, not overwritten)"
        continue
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        info "  DRY-RUN: sudo -u $PG_USER pg_dump --format=custom --file=$DUMP_FILE $DB"
    else
        sudo -u "$PG_USER" pg_dump --format=custom --file="$DUMP_FILE" "$DB" \
            || die "pg_dump failed for $DB" 1
        SIZE=$(du -h "$DUMP_FILE" | cut -f1)
        pass "  $DB ($SIZE)"
        _sk_audit "pg_dump custom backup of $DB -> $DUMP_FILE"
    fi
done

# --- Step 5: WAL archive sanity check (optional) ----------------------------
header "Step 4/4: WAL archive check"
if [[ -z "$WAL_ARCHIVE_DIR" ]]; then
    info "WAL archive check disabled (no --wal-archive)"
elif [[ ! -d "$WAL_ARCHIVE_DIR" ]]; then
    warn "WAL archive dir does not exist: $WAL_ARCHIVE_DIR"
else
    WAL_COUNT=$(find "$WAL_ARCHIVE_DIR" -type f 2>/dev/null | wc -l)
    if (( WAL_COUNT > 0 )); then
        pass "WAL archive has $WAL_COUNT file(s) in $WAL_ARCHIVE_DIR"
    else
        warn "WAL archive dir is EMPTY: $WAL_ARCHIVE_DIR (archive_command may be failing)"
    fi
fi

# --- Rotation ----------------------------------------------------------------
header "Rotation: pruning old dumps"
if [[ "$DRY_RUN" == "1" ]]; then
    info "DRY-RUN: would prune *.dump / globals_*.sql older than $RETENTION_DAYS days in $BACKUP_DIR"
else
    find "$BACKUP_DIR" -maxdepth 1 -type f \( -name '*.dump' -o -name 'globals_*.sql' \) \
        -mtime "+${RETENTION_DAYS}" -print -delete 2>/dev/null \
        | while read -r f; do info "  pruned: $f"; done
fi

print_summary
pass "backup completed successfully"
exit 0
