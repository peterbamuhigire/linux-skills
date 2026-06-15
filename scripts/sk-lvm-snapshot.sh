#!/usr/bin/env bash
#: Title:       sk-lvm-snapshot
#: Synopsis:    sk-lvm-snapshot --lv /dev/VG/LV --out ARCHIVE [--size 5G] [--yes]
#: Description: Take a sized LVM COW snapshot of an LV, mount it read-only, tar
#:              it (--acls --xattrs) to a backup path, then unmount and lvremove
#:              the snapshot. Checks VG free space and warns if the COW size is
#:              under 10% of the origin. Asks before creating and before
#:              removing. Works on Debian/Ubuntu and the RHEL family (LVM is
#:              identical on both). See
#:              13-backup-and-archiving/linux-filesystem-snapshots/references/lvm-snapshots.md.
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
LV=""
OUT=""
SNAP_SIZE="5G"
SNAP_NAME=""
MOUNT_DIR=""
SNAP_DEV=""

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-lvm-snapshot --lv /dev/VG/LV --out ARCHIVE [OPTIONS]

Take an LVM snapshot of a logical volume, back it up to a tar.gz, then release
the snapshot. Works on Debian/Ubuntu and the RHEL family.

REQUIRED:
        --lv PATH       Origin logical volume, e.g. /dev/data/web
        --out ARCHIVE   Output archive path, e.g. /backups/web.tar.gz

OPTIONS:
        --size SIZE     COW snapshot size (default 5G). Should be >= 10-20%
                        of the origin LV; the script warns if it is too small.

STANDARD FLAGS:
    -h, --help          Show this help and exit
        --version       Print version
    -y, --yes           Non-interactive; requires --lv and --out
    -n, --dry-run       Print the steps, change nothing
        --log           Tee output to /var/log/linux-skills/
    -v, --verbose       Extra diagnostic output
    -q, --quiet         Errors and final result only

EXIT CODES:
    0  success
    2  usage / flag error
    3  precondition failed (not root, no LVM, LV not found)
    4  user aborted
    5  dependency missing (lvm/tar)

EXAMPLE:
    sudo sk-lvm-snapshot --lv /dev/data/web --out /backups/web.tar.gz --size 8G

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

cleanup_snapshot() {
    # Registered cleanup: unmount and remove the snapshot if still present.
    [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]] && mountpoint -q "$MOUNT_DIR" 2>/dev/null \
        && umount "$MOUNT_DIR" 2>/dev/null || true
    [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]] && rmdir "$MOUNT_DIR" 2>/dev/null || true
    [[ -n "$SNAP_DEV" ]] && lvremove -f "$SNAP_DEV" 2>/dev/null || true
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
parse_standard_flags "$@"

while [[ ${#REMAINING_ARGS[@]} -gt 0 ]]; do
    case "${REMAINING_ARGS[0]}" in
        --lv)
            LV="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --out)
            OUT="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --size)
            SNAP_SIZE="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        *)
            die "unknown argument: ${REMAINING_ARGS[0]} (see --help)" 2
            ;;
    esac
done

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_root
require_family any
require_cmd lvcreate lvremove lvs tar
require_flag LV
require_flag OUT
[[ -n "$LV" && -n "$OUT" ]] || die "--lv and --out are required (see --help)" 2
[[ -b "$LV" ]] || die "logical volume not found (not a block device): $LV" 3

# Derive VG and a snapshot name
VG="$(lvs --noheadings -o vg_name "$LV" 2>/dev/null | tr -d ' ')"
[[ -n "$VG" ]] || die "could not determine VG for $LV (is it an LVM LV?)" 3
SNAP_NAME="$(basename "$LV")-snap-$(date +%Y%m%d-%H%M%S)"
SNAP_DEV="/dev/${VG}/${SNAP_NAME}"

# Warn if COW size is under ~10% of the origin
ORIGIN_BYTES="$(lvs --noheadings --units b -o lv_size "$LV" 2>/dev/null | tr -dc '0-9')"
SNAP_BYTES="$(numfmt --from=iec "${SNAP_SIZE%[Bb]}" 2>/dev/null || echo 0)"
if [[ -n "$ORIGIN_BYTES" && "$SNAP_BYTES" -gt 0 ]]; then
    if (( SNAP_BYTES * 10 < ORIGIN_BYTES )); then
        warn "COW size $SNAP_SIZE is under 10% of the origin LV; a busy volume may fill it and invalidate the snapshot"
    fi
fi

info "origin LV : $LV  (VG: $VG)"
info "snapshot  : $SNAP_DEV  (COW size: $SNAP_SIZE)"
info "archive   : $OUT"

if [[ -e "$OUT" ]]; then
    confirm "Archive $OUT exists — overwrite?" N || die "user aborted" 4
fi
confirm "Create snapshot, back it up, then remove it?" Y || die "user aborted" 4

# Register cleanup so a failure mid-way still releases the snapshot.
sk_on_exit cleanup_snapshot

# =============================================================================
# 6. Create snapshot
# =============================================================================
header "Create LVM snapshot"
run lvcreate -L "$SNAP_SIZE" -s -n "$SNAP_NAME" "$LV" \
    || die "lvcreate failed (check VG free space: vgs $VG)" 1
pass "snapshot created: $SNAP_DEV"

# =============================================================================
# 7. Mount read-only + archive
# =============================================================================
MOUNT_DIR="$(safe_tempdir sk-lvmsnap)"
header "Mount snapshot read-only and archive"
# nouuid is required for XFS (duplicate UUID); harmless to try and fall back.
if ! run mount -o ro,nouuid "$SNAP_DEV" "$MOUNT_DIR" 2>/dev/null; then
    run mount -o ro "$SNAP_DEV" "$MOUNT_DIR" || die "failed to mount snapshot" 1
fi
pass "mounted $SNAP_DEV at $MOUNT_DIR (ro)"

if ! run tar --acls --xattrs -czf "$OUT" -C "$MOUNT_DIR" .; then
    die "tar of snapshot failed" 1
fi
[[ "$DRY_RUN" != "1" ]] && pass "archive written: $OUT ($(stat -c%s "$OUT" 2>/dev/null || echo '?') bytes)"

# =============================================================================
# 8. Release snapshot (cleanup_snapshot also runs on exit as a backstop)
# =============================================================================
header "Release snapshot"
run umount "$MOUNT_DIR" || warn "umount $MOUNT_DIR failed (will retry on cleanup)"
run lvremove -f "$SNAP_DEV" && SNAP_DEV="" && pass "snapshot removed" \
    || warn "lvremove failed (will retry on cleanup)"

header "Result"
pass "done — verify the archive with: sk-tar-verify --check $OUT"
exit 0
