#!/usr/bin/env bash
#: Title:       sk-pg-backup
#: Synopsis:    sk-pg-backup [--db NAME|--all] [--backup-dir DIR] [--yes] [--dry-run]
#: Description: Logical backup of PostgreSQL. Dumps one database (--db) or every
#:              database (--all, default) with pg_dump --format=custom to a
#:              timestamped file, plus pg_dumpall --globals-only to capture roles
#:              and tablespaces. Compressed custom format is restorable with
#:              pg_restore (selective/parallel). Optional WAL-archive sanity check.
#:              Read-only against the database: it dumps, never drops or modifies
#:              data. Every artefact is written mode 0600 through a private staging
#:              directory and only renamed into place after pg_restore --list can
#:              read it. Dumps are NOT encrypted. Interactive by default; --yes
#:              for cron. Both families.
#: Author:      Peter Bamuhigire <techguypeter.com>
#: Contact:     +256784464178
#: Version:     0.2.0

# =============================================================================
# 1. Library + safety
# =============================================================================
set -uo pipefail
umask 077

SK_LIB="/usr/local/lib/linux-skills/common.sh"
if [[ ! -f "$SK_LIB" ]]; then
    _SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SK_LIB="${_SD}/lib/common.sh"
fi
# shellcheck source=/dev/null
source "$SK_LIB" || { echo "FATAL: cannot source common.sh" >&2; exit 5; }
# The installed library may predate this script; fail with a clear remedy, not "command not found".
declare -F sk_source_trusted_config >/dev/null \
    || { echo "FATAL: $SK_LIB is older than this script (no sk_source_trusted_config). Run: sudo install-skills-bin core" >&2; exit 5; }

# =============================================================================
# 2. Defaults
# =============================================================================
# Read by parse_standard_flags in the sourced shared library.
# shellcheck disable=SC2034
SCRIPT_VERSION="0.2.0"

# Run dumps as the postgres OS user (peer auth) unless overridden.
PG_USER="${PG_USER:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/postgresql}"
TARGET_DB="${TARGET_DB:-}"        # empty + ALL_DBS=1 means dump every database
ALL_DBS=1
RETENTION_DAYS="${RETENTION_DAYS:-7}"
WAL_ARCHIVE_DIR="${WAL_ARCHIVE_DIR:-}"   # if set, sanity-check it is non-empty

CONFIG_FILE="${SK_PG_BACKUP_CONFIG:-/etc/linux-skills/pg-backup.conf}"

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

Files are written mode 0600 (the globals file holds role password hashes) via a
private staging directory, checked with pg_restore --list, then renamed into
BACKUP_DIR. A failed or unreadable dump is never published. The globals file is
published first, so a run that fails on a later database can leave a globals file
with no dumps beside it: that file is not a backup of any database. Dumps are not
encrypted: protect BACKUP_DIR and any copy of it accordingly.

CONFIG:
    Reads /etc/linux-skills/pg-backup.conf if present and refuses it unless it
    is root-owned, not group/world-writable and not a symlink (exit 3). The file
    overrides environment variables; flags override the file. Settings:
        PG_USER             OS user to run dumps as (peer auth; default: postgres)
        BACKUP_DIR          Local backup directory (default: /var/backups/postgresql)
        RETENTION_DAYS      Prune dumps older than this many days (default: 7)
        WAL_ARCHIVE_DIR     If set, verify the WAL archive dir is non-empty
    SK_PG_BACKUP_CONFIG names a different configuration file (tests, unusual layouts).

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
    5  dependency missing (pg_dump / pg_dumpall / pg_restore / psql)

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
    sk_source_trusted_config "$CONFIG_FILE"
    case $? in
        0) info "loaded config from $CONFIG_FILE" ;;
        1) ;;
        *) die "untrusted configuration file: $CONFIG_FILE (owner root, no group/other write, not a symlink)" 3 ;;
    esac
}

# Remove the private staging directory, whatever the exit path. Nothing the
# script stages is ever left under a name that looks like a finished backup.
cleanup_staging() {
    if [[ -n "${STAGING_DIR:-}" ]] && ! rm -rf -- "$STAGING_DIR" 2>/dev/null; then
        fail "could not remove private staging directory: $STAGING_DIR"
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

# Run a PostgreSQL client as $PG_USER from "/". Debian's pg_wrapper prints
# 'could not change directory to "<cwd>": Permission denied' for every call made from a
# directory the postgres user cannot enter, and cron starts root's jobs in /root, so each run
# would mail two warnings per database. Redirects stay with the calling (root) shell.
as_pg() { ( cd / && sudo -u "$PG_USER" "$@" ); }

# File-name-safe form of a database name. A name that needed changing gets a
# checksum suffix so two different names cannot collide on one file.
safe_db_name() {
    local name="$1" safe
    safe="${name//[^[:alnum:]_.-]/_}"
    if [[ "$safe" != "$name" ]]; then
        safe="${safe}_$(printf '%s' "$name" | cksum | cut -d' ' -f1)"
    fi
    printf '%s' "$safe"
}

# Move a finished, checked staging file into BACKUP_DIR (same filesystem, so the
# rename is atomic) and confirm it is private.
publish_staged() {
    local staged="$1" final="$2" mode
    mode="$(stat -c '%a' -- "$staged")" || die "cannot inspect $staged" 1
    [[ "$mode" == "600" ]] || die "$staged has mode $mode, expected 600; not publishing it" 1
    mv -- "$staged" "$final" || die "cannot move $staged to $final" 1
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
parse_standard_flags "$@"
load_config

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
require_family any        # runs on Debian/Ubuntu and the RHEL family
require_cmd pg_dump pg_dumpall pg_restore psql find stat date mkdir mktemp mv chmod rm du cut wc cksum

if [[ "$ALL_DBS" == "0" ]]; then
    require_flag TARGET_DB
fi

[[ "$BACKUP_DIR" == /* ]] || die "BACKUP_DIR must be an absolute path" 2
case "$RETENTION_DAYS" in
    ''|*[!0-9]*) die "RETENTION_DAYS must be a positive whole number of days" 2 ;;
    *[1-9]*) ;;
    *) die "RETENTION_DAYS must be greater than zero" 2 ;;
esac

# =============================================================================
# 6. Main logic
# =============================================================================

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
STAGING_DIR=""
GLOBALS_NAME="globals_$TIMESTAMP.sql"
GLOBALS_FILE="$BACKUP_DIR/$GLOBALS_NAME"

sk_on_exit cleanup_staging

header "sk-pg-backup — ${HOSTNAME:-unknown}"
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

# --- Step 1: Ensure private backup and staging directories -------------------
if [[ "$DRY_RUN" == "1" ]]; then
    info "DRY-RUN would create $BACKUP_DIR (mode 0700 if new) and a private staging directory under it"
else
    # umask 077 also protects any intermediate directories created by -p.
    # shellcheck disable=SC2174
    mkdir -m 0700 -p -- "$BACKUP_DIR" || die "cannot create backup directory: $BACKUP_DIR" 1
    dir_mode="$(stat -c '%a' -- "$BACKUP_DIR")" || die "cannot inspect $BACKUP_DIR" 1
    if (( (8#$dir_mode & 077) != 0 )); then
        warn "$BACKUP_DIR has mode $dir_mode: other users can list backup names. Files are written 0600."
    fi
    STAGING_DIR="$(mktemp -d "$BACKUP_DIR/.pg-backup.XXXXXXXX")" \
        || die "cannot create private staging directory under $BACKUP_DIR" 1
    chmod 0700 "$STAGING_DIR" || die "cannot protect staging directory: $STAGING_DIR" 1
fi

# --- Step 2: Enumerate databases --------------------------------------------
header "Step 1/4: Enumerating databases"
DATABASES=()
if [[ "$ALL_DBS" == "1" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
        info "DRY-RUN: would list databases via psql"
    else
        # NUL-separated so a database name can hold any character.
        as_pg psql -A -t -0 -c \
            "SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres';" \
            > "$STAGING_DIR/databases.list" 2>/dev/null \
            || die "cannot connect to PostgreSQL as $PG_USER" 1
        mapfile -d '' -t DATABASES < "$STAGING_DIR/databases.list"
        if (( ${#DATABASES[@]} == 0 )); then
            die "no user databases found" 1
        fi
        info "${#DATABASES[@]} database(s) to back up (the postgres maintenance database is not included)"
    fi
else
    DATABASES=("$TARGET_DB")
fi

# --- Step 3: Dump globals (roles, tablespaces) ------------------------------
header "Step 2/4: Dumping globals (roles, tablespaces)"
if ask_overwrite "$GLOBALS_FILE"; then
    if [[ "$DRY_RUN" == "1" ]]; then
        info "DRY-RUN: would write $GLOBALS_FILE (mode 0600)"
    else
        # The redirect is opened by this shell under umask 077, so the file is
        # 0600 whatever umask the postgres user has.
        as_pg pg_dumpall --globals-only > "$STAGING_DIR/$GLOBALS_NAME" \
            || die "pg_dumpall --globals-only failed" 1
        [[ -s "$STAGING_DIR/$GLOBALS_NAME" ]] || die "pg_dumpall --globals-only produced an empty file" 1
        publish_staged "$STAGING_DIR/$GLOBALS_NAME" "$GLOBALS_FILE"
        pass "globals: $GLOBALS_FILE"
    fi
else
    info "skipped globals (file exists, not overwritten)"
fi

# --- Step 4: Dump each database (custom format) -----------------------------
header "Step 3/4: Dumping databases (pg_dump --format=custom)"
for DB in ${DATABASES[@]+"${DATABASES[@]}"}; do
    DUMP_NAME="$(safe_db_name "$DB")_$TIMESTAMP.dump"
    DUMP_FILE="$BACKUP_DIR/$DUMP_NAME"
    info "  dumping $DB -> $DUMP_FILE"
    if ! ask_overwrite "$DUMP_FILE"; then
        info "  skipped $DB (file exists, not overwritten)"
        continue
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        info "  DRY-RUN: sudo -u $PG_USER pg_dump --format=custom $DB > $DUMP_FILE"
    else
        as_pg pg_dump --format=custom -- "$DB" > "$STAGING_DIR/$DUMP_NAME" \
            || die "pg_dump failed for $DB" 1
        [[ -s "$STAGING_DIR/$DUMP_NAME" ]] || die "pg_dump produced an empty file for $DB" 1
        pg_restore --list "$STAGING_DIR/$DUMP_NAME" > /dev/null \
            || die "pg_restore --list cannot read the dump of $DB; not publishing it" 1
        publish_staged "$STAGING_DIR/$DUMP_NAME" "$DUMP_FILE"
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
# Only this script's own names are eligible: <database>_YYYYMMDD-HHMMSS.dump and
# globals_YYYYMMDD-HHMMSS.sql. Any other file in BACKUP_DIR is left alone.
header "Rotation: pruning old dumps"
if [[ "$DRY_RUN" == "1" ]]; then
    info "DRY-RUN: would prune this script's dumps and globals files older than $RETENTION_DAYS days in $BACKUP_DIR"
else
    PRUNED="$(find "$BACKUP_DIR" -maxdepth 1 -type f -regextype posix-extended \
        -regex '.*/([^/]+_[0-9]{8}-[0-9]{6}\.dump|globals_[0-9]{8}-[0-9]{6}\.sql)' \
        -mtime "+${RETENTION_DAYS}" -print -delete)" || die "local backup retention failed" 1
    if [[ -n "$PRUNED" ]]; then
        while IFS= read -r f; do info "  pruned: $f"; done <<< "$PRUNED"
    fi
fi

print_summary
if [[ "$DRY_RUN" == "1" ]]; then
    pass "dry-run completed; no backup was written"
else
    pass "backup completed successfully"
fi
exit 0
