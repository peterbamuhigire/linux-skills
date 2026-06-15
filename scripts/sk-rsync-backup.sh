#!/usr/bin/env bash
#: Title:       sk-rsync-backup
#: Synopsis:    sk-rsync-backup --src DIR --dst DEST [--mirror|--snapshot] [--bwlimit KBPS]
#:              [--exclude-from FILE] [--ssh] [--dry-run] [--yes]
#: Description: Dry-run-first rsync wrapper for offsite/incremental backups on
#:              Debian/Ubuntu or the RHEL family. ALWAYS previews the transfer
#:              with --dry-run and asks before a real run. --mirror adds --delete
#:              (an exact copy); --snapshot creates a hard-linked --link-dest
#:              snapshot under DEST/<date>/. bwlimit-aware. Verifies with a
#:              post-run dry-run. See
#:              13-backup-and-archiving/linux-rsync-sync/references/.
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
SRC=""
DST=""
MODE="copy"          # copy | mirror | snapshot
BWLIMIT=""
EXCLUDE_FROM=""
USE_SSH=0

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-rsync-backup --src DIR --dst DEST [OPTIONS]

Dry-run-first rsync wrapper. Previews every transfer with --dry-run and asks
before running for real. Works on Debian/Ubuntu and the RHEL family.

REQUIRED:
        --src DIR       Source directory (a trailing slash means "contents of")
        --dst DEST      Destination: local path, or user@host:path with --ssh

MODES (default: plain copy, no deletion):
        --mirror        Exact mirror: adds --delete (removes extra files on dst)
        --snapshot      Hard-linked incremental snapshot under DEST/<YYYY-MM-DD>/
                        using --link-dest against the most recent prior snapshot

OPTIONS:
        --bwlimit KBPS  Throttle transfer to KBPS KB/s (e.g. 5000)
        --exclude-from FILE   Read exclude patterns from FILE
        --ssh           Treat --dst as a remote target over ssh

STANDARD FLAGS:
    -h, --help          Show this help and exit
        --version       Print version
    -y, --yes           Non-interactive; requires --src and --dst
    -n, --dry-run       Preview only, never run the real transfer
        --log           Tee output to /var/log/linux-skills/
    -v, --verbose       Extra diagnostic output
    -q, --quiet         Errors and final result only

EXIT CODES:
    0  success
    2  usage / flag error
    4  user aborted
    5  dependency missing (rsync)

EXAMPLES:
    sudo sk-rsync-backup --src /var/www/ --dst /mnt/backup/www/ --dry-run
    sudo sk-rsync-backup --src /var/www/ --dst /mnt/backup/www/ --mirror
    sudo sk-rsync-backup --src /var/www/ --dst /mnt/backup/snapshots --snapshot
    sudo sk-rsync-backup --src /var/www/ --dst backup@offsite:/srv/www/ --ssh --bwlimit 5000

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
parse_standard_flags "$@"

while [[ ${#REMAINING_ARGS[@]} -gt 0 ]]; do
    case "${REMAINING_ARGS[0]}" in
        --src)
            SRC="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --dst)
            DST="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --mirror)
            MODE="mirror"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
            ;;
        --snapshot)
            MODE="snapshot"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
            ;;
        --bwlimit)
            BWLIMIT="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --exclude-from)
            EXCLUDE_FROM="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --ssh)
            USE_SSH=1
            REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
            ;;
        *)
            die "unknown argument: ${REMAINING_ARGS[0]} (see --help)" 2
            ;;
    esac
done

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_cmd rsync
require_flag SRC
require_flag DST
[[ -n "$SRC" ]] || die "--src is required (see --help)" 2
[[ -n "$DST" ]] || die "--dst is required (see --help)" 2

if [[ "$USE_SSH" != "1" && ! -d "$SRC" ]]; then
    die "source directory not found: $SRC" 2
fi
if [[ -n "$EXCLUDE_FROM" && ! -f "$EXCLUDE_FROM" ]]; then
    die "exclude-from file not found: $EXCLUDE_FROM" 2
fi

# =============================================================================
# 6. Build the rsync argument list
# =============================================================================
RSYNC_OPTS=(-a)
[[ "$VERBOSE" == "1" ]] && RSYNC_OPTS+=(-v --stats)
[[ -n "$BWLIMIT" ]] && RSYNC_OPTS+=(--bwlimit="$BWLIMIT")
[[ -n "$EXCLUDE_FROM" ]] && RSYNC_OPTS+=(--exclude-from="$EXCLUDE_FROM")
[[ "$USE_SSH" == "1" ]] && RSYNC_OPTS+=(-e ssh -z)

TARGET="$DST"
case "$MODE" in
    mirror)
        RSYNC_OPTS+=(--delete)
        ;;
    snapshot)
        if [[ "$USE_SSH" == "1" ]]; then
            die "--snapshot is local-only (--link-dest needs same filesystem); drop --ssh" 2
        fi
        TODAY="${DST%/}/$(date +%F)"
        LAST="$(find "${DST%/}" -maxdepth 1 -type d -name '20*' 2>/dev/null | sort | tail -1)"
        RSYNC_OPTS+=(--delete)
        [[ -n "$LAST" && "$LAST" != "$TODAY" ]] && RSYNC_OPTS+=(--link-dest="$LAST")
        TARGET="${TODAY}/"
        info "snapshot target: $TARGET"
        [[ -n "$LAST" ]] && info "linking unchanged files against: $LAST"
        run mkdir -p "$TARGET"
        ;;
esac

# =============================================================================
# 7. Always dry-run first
# =============================================================================
header "Preview (rsync --dry-run)"
rsync -n "${RSYNC_OPTS[@]}" "$SRC" "$TARGET" || die "rsync dry-run failed" 1

if [[ "$DRY_RUN" == "1" ]]; then
    header "Result"
    pass "dry run only — nothing transferred (mode: $MODE)"
    exit 0
fi

# =============================================================================
# 8. Confirm + run for real
# =============================================================================
if [[ "$MODE" == "mirror" ]]; then
    confirm_destructive "Mirror $SRC -> $TARGET (this DELETES extra files on the destination)?" \
        || die "user aborted" 4
else
    confirm "Run rsync $SRC -> $TARGET now?" Y || die "user aborted" 4
fi

header "Transfer"
run rsync "${RSYNC_OPTS[@]}" "$SRC" "$TARGET" || die "rsync transfer failed" 1
pass "transfer complete"

# =============================================================================
# 9. Verify with a post-run dry-run
# =============================================================================
header "Verify (post-run dry-run should report no changes)"
VERIFY_OPTS=(-a)
[[ -n "$EXCLUDE_FROM" ]] && VERIFY_OPTS+=(--exclude-from="$EXCLUDE_FROM")
[[ "$USE_SSH" == "1" ]] && VERIFY_OPTS+=(-e ssh)
[[ "$MODE" == "mirror" ]] && VERIFY_OPTS+=(--delete)
if rsync -ni "${VERIFY_OPTS[@]}" "$SRC" "$TARGET" | grep -q .; then
    warn "destination still differs from source (see itemized output above)"
else
    pass "destination matches source"
fi

header "Result"
pass "done (mode: $MODE)"
exit 0
