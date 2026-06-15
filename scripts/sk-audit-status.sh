#!/usr/bin/env bash
#: Title:       sk-audit-status
#: Synopsis:    sk-audit-status [--top N]
#: Description: Read-only health report for the Linux Audit daemon (auditd) on
#:              Debian/Ubuntu and RHEL-family (Fedora, RHEL, CentOS Stream, Rocky,
#:              Alma, Oracle) servers. Reports daemon state, enabled/immutable
#:              flag, failure mode, loaded rule count, backlog and LOST counters,
#:              the top audit keys by event volume (aureport -k), and recent
#:              SELinux AVC denials on the RHEL family. Changes nothing — it only
#:              runs auditctl/ausearch/aureport in read mode.
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
TOP=10                     # --top N : how many keys to show in the breakdown

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-audit-status [OPTIONS]

Read-only auditd health report on Debian/Ubuntu and RHEL-family servers:
daemon state, enabled/immutable flag, failure mode, loaded rule count,
backlog/LOST counters, top keys by event volume, and recent SELinux AVC
denials (RHEL family). Changes nothing.

OPTIONS:
        --top N          Show the top N audit keys by event count (default 10).

STANDARD FLAGS:
    -h, --help           Show this help and exit
        --version        Print version
    -y, --yes            Non-interactive mode
    -n, --dry-run        Print what would run, change nothing
        --log            Tee output to /var/log/linux-skills/
    -v, --verbose        Extra diagnostic output
    -q, --quiet          Errors and final result only

EXIT CODES:
    0  report produced, auditd healthy (enabled, no losses)
    1  report produced, but a concern was flagged (disabled, or LOST > 0)
    3  precondition failed (not root, or unsupported distro)
    5  dependency missing (auditctl not installed)

EXAMPLES:
    sudo sk-audit-status
    sudo sk-audit-status --top 20

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
        --top)
            TOP="${REMAINING_ARGS[1]:-}"
            [[ "$TOP" =~ ^[0-9]+$ ]] || die "--top needs a number (see --help)" 2
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --top=*)
            TOP="${REMAINING_ARGS[0]#*=}"
            [[ "$TOP" =~ ^[0-9]+$ ]] || die "--top needs a number (see --help)" 2
            REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
            ;;
        *)
            die "Unknown argument: ${REMAINING_ARGS[0]} (see --help)" 2
            ;;
    esac
done

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_root
require_family any
require_cmd auditctl

# =============================================================================
# 6. Main logic
# =============================================================================
CONCERN=0

header "auditd status — $(hostname) — $(date '+%Y-%m-%d %H:%M:%S')"
# shellcheck disable=SC1091
info "OS: $(. /etc/os-release && echo "$PRETTY_NAME") | family: $SK_DISTRO_FAMILY"

# --- Daemon / kernel audit status --------------------------------------------
header "Daemon and kernel audit status"
if systemctl is-active --quiet auditd 2>/dev/null; then
    pass "auditd service is active."
else
    warn "auditd service is not active (systemctl status auditd)."
    CONCERN=1
fi

STATUS="$(auditctl -s 2>/dev/null || true)"
if [[ -n "$STATUS" ]]; then
    printf '%s\n' "$STATUS" | sed 's/^/         /'

    ENABLED="$(printf '%s\n' "$STATUS" | awk '/^enabled/ {print $2; exit}')"
    LOST="$(printf '%s\n' "$STATUS" | awk '/^lost/ {print $2; exit}')"
    BACKLOG="$(printf '%s\n' "$STATUS" | awk '/^backlog / {print $2; exit}')"

    case "${ENABLED:-}" in
        2) pass "Auditing is ENABLED and IMMUTABLE (enabled=2) — rules locked until reboot." ;;
        1) pass "Auditing is enabled (enabled=1). Consider -e 2 for production immutability." ;;
        0) warn "Auditing is DISABLED (enabled=0)."; CONCERN=1 ;;
        *) info "enabled flag: ${ENABLED:-unknown}" ;;
    esac

    if [[ "${LOST:-0}" =~ ^[0-9]+$ ]] && (( LOST > 0 )); then
        warn "LOST events: $LOST — auditd is dropping events. Raise the buffer (-b) or narrow rules."
        CONCERN=1
    else
        pass "No lost events (lost=${LOST:-0})."
    fi
    [[ -n "${BACKLOG:-}" ]] && info "Current backlog: $BACKLOG"
else
    warn "auditctl -s returned nothing (kernel audit unavailable?)."
    CONCERN=1
fi

# --- Loaded rules ------------------------------------------------------------
header "Loaded rules"
RULES="$(auditctl -l 2>/dev/null || true)"
if [[ -z "$RULES" || "$RULES" == "No rules" ]]; then
    warn "No audit rules are loaded. See linux-auditd-rules (references/auditd-reference.md)."
    CONCERN=1
else
    RCOUNT="$(printf '%s\n' "$RULES" | grep -c . || true)"
    pass "$RCOUNT rule(s) loaded."
    if (( VERBOSE == 1 )); then
        printf '%s\n' "$RULES" | sed 's/^/         /'
    fi
fi

# --- Top keys by event volume ------------------------------------------------
header "Top $TOP audit keys by event volume"
if command -v aureport >/dev/null 2>&1; then
    # aureport -k --summary lists keys with counts; skip header lines.
    KOUT="$(aureport -k --summary 2>/dev/null | awk 'NF==2 && $1 ~ /^[0-9]+$/ {print}' | sort -rn | head -n "$TOP" || true)"
    if [[ -n "$KOUT" ]]; then
        printf '%s\n' "$KOUT" | sed 's/^/         /'
    else
        info "No keyed events recorded yet (rules may be new, or no matching activity)."
    fi
else
    info "aureport not available — skipping key breakdown."
fi

# --- SELinux AVC denials (RHEL family) ---------------------------------------
if [[ "$SK_DISTRO_FAMILY" == "rhel" ]]; then
    header "Recent SELinux AVC denials (RHEL family)"
    if command -v ausearch >/dev/null 2>&1; then
        AVC="$(ausearch -m AVC -ts recent 2>/dev/null | grep -c '^type=AVC' || true)"
        if [[ "${AVC:-0}" =~ ^[0-9]+$ ]] && (( AVC > 0 )); then
            warn "$AVC recent AVC denial(s) — investigate with: ausearch -m AVC -ts recent"
        else
            pass "No recent AVC denials."
        fi
    else
        info "ausearch not available — skipping AVC check."
    fi
fi

# =============================================================================
# 7. Summary
# =============================================================================
print_summary
if (( CONCERN == 1 )); then
    warn "One or more concerns flagged above — review before relying on the audit trail."
    exit 1
fi
pass "auditd looks healthy."
exit 0
