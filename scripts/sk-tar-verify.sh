#!/usr/bin/env bash
#: Title:       sk-tar-verify
#: Synopsis:    sk-tar-verify --src DIR --out ARCHIVE [--xz] [--compare] [--yes]
#:              sk-tar-verify --check ARCHIVE
#: Description: Create a metadata-preserving tar archive (--acls --xattrs
#:              --numeric-owner; gzip default, --xz for best ratio) then VERIFY
#:              it: list it (tar -tvf), write a .sha256 sidecar, and optionally
#:              --compare against the source tree. In --check mode, verify an
#:              existing archive (list + sha256). Works on Debian/Ubuntu and the
#:              RHEL family. See
#:              13-backup-and-archiving/linux-archive-integrity/references/.
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
OUT=""
CHECK=""
USE_XZ=0
DO_COMPARE=0

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-tar-verify --src DIR --out ARCHIVE [OPTIONS]   (create + verify)
       sk-tar-verify --check ARCHIVE                     (verify existing)

Create a metadata-preserving tar archive (--acls --xattrs --numeric-owner) and
verify it, or verify an existing archive. Works on Debian/Ubuntu and the RHEL
family.

CREATE MODE:
        --src DIR       Directory tree to archive
        --out ARCHIVE   Output path (e.g. /backups/www.tar.gz)
        --xz            Use xz compression (best ratio, slow) instead of gzip
        --compare       After create, run tar --compare against the source

CHECK MODE:
        --check ARCHIVE Verify an existing archive (tar -tvf + sha256 -c)

STANDARD FLAGS:
    -h, --help          Show this help and exit
        --version       Print version
    -y, --yes           Non-interactive; overwrite existing archive without ask
    -n, --dry-run       Print what would happen, create nothing
        --log           Tee output to /var/log/linux-skills/
    -v, --verbose       Extra diagnostic output
    -q, --quiet         Errors and final result only

EXIT CODES:
    0  success
    2  usage / flag error
    4  user aborted
    5  dependency missing (tar/sha256sum)

EXAMPLES:
    sudo sk-tar-verify --src /var/www --out /backups/www.tar.gz --compare
    sudo sk-tar-verify --src /etc --out /backups/etc.tar.xz --xz
    sk-tar-verify --check /backups/www.tar.gz

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
        --out)
            OUT="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --check)
            CHECK="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --xz)
            USE_XZ=1
            REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
            ;;
        --compare)
            DO_COMPARE=1
            REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
            ;;
        *)
            die "unknown argument: ${REMAINING_ARGS[0]} (see --help)" 2
            ;;
    esac
done

require_cmd tar sha256sum

# =============================================================================
# 5. CHECK mode — verify an existing archive
# =============================================================================
if [[ -n "$CHECK" ]]; then
    [[ -f "$CHECK" ]] || die "archive not found: $CHECK" 2

    header "List archive contents (tar -tvf)"
    if run tar -tvf "$CHECK" >/dev/null; then
        pass "archive is readable and complete"
    else
        die "archive failed to list — corrupt or truncated" 1
    fi

    header "sha256 verification"
    if [[ -f "${CHECK}.sha256" ]]; then
        if ( cd "$(dirname "$CHECK")" && sha256sum -c "$(basename "$CHECK").sha256" ); then
            pass "sha256 matches sidecar"
        else
            fail "sha256 MISMATCH — archive changed since creation"
        fi
    else
        warn "no ${CHECK}.sha256 sidecar found; cannot verify integrity digest"
    fi

    header "Result"
    print_summary
    (( FAIL_COUNT == 0 )) || exit 1
    exit 0
fi

# =============================================================================
# 6. CREATE mode — sanity checks
# =============================================================================
[[ -n "$SRC" && -n "$OUT" ]] || die "create mode needs --src and --out (or use --check)" 2
require_flag SRC
require_flag OUT
[[ -d "$SRC" ]] || die "source directory not found: $SRC" 2

if [[ -e "$OUT" ]]; then
    confirm "Archive $OUT exists — overwrite?" N || die "user aborted" 4
fi

# Compression letter
COMP="z"; [[ "$USE_XZ" == "1" ]] && COMP="J"

# tar -C handling: archive the basename relative to its parent so paths are
# relocatable (e.g. archive 'www', not '/var/www').
PARENT="$(cd "$(dirname "$SRC")" && pwd)"
BASE="$(basename "$SRC")"

TAR_OPTS=(--acls --xattrs --numeric-owner)
# SELinux contexts ride along as xattrs on RHEL; harmless flag elsewhere if
# supported, so only add it on the rhel family.
detect_distro
[[ "$SK_DISTRO_FAMILY" == "rhel" ]] && TAR_OPTS+=(--selinux)

# =============================================================================
# 7. Create
# =============================================================================
header "Create archive"
info "tar -c${COMP}f $OUT  (${TAR_OPTS[*]})  from $PARENT/$BASE"
if ! run tar "${TAR_OPTS[@]}" -c${COMP}f "$OUT" -C "$PARENT" "$BASE"; then
    die "archive creation failed" 1
fi
[[ "$DRY_RUN" == "1" ]] && { header "Result"; pass "dry run only"; exit 0; }
pass "archive created: $OUT ($(stat -c%s "$OUT" 2>/dev/null || echo '?') bytes)"

# =============================================================================
# 8. Verify: list + sha256 (+ optional compare)
# =============================================================================
header "Verify: list (tar -tvf)"
if tar -tvf "$OUT" >/dev/null; then
    pass "archive lists cleanly"
else
    fail "archive failed to list"
fi

header "Verify: sha256 sidecar"
( cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256" ) \
    && pass "wrote ${OUT}.sha256" \
    || fail "could not write sha256 sidecar"

if [[ "$DO_COMPARE" == "1" ]]; then
    header "Verify: compare against source (tar --compare)"
    if tar --acls --xattrs --compare -f "$OUT" -C "$PARENT" >/dev/null 2>&1; then
        pass "archive matches source tree"
    else
        warn "tar --compare reported differences (source may have changed since create)"
    fi
fi

header "Result"
print_summary
(( FAIL_COUNT == 0 )) || exit 1
exit 0
