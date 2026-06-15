#!/usr/bin/env bash
#: Title:       sk-rootkit-scan
#: Synopsis:    sk-rootkit-scan [--update-baseline] [--quick] [--yes] [--log]
#: Description: Run rootkit scanners (rkhunter and chkrootkit) on Debian/Ubuntu
#:              and RHEL-family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle)
#:              servers, summarise warnings, and surface likely-real findings.
#:              Read-only by default. With --update-baseline it runs
#:              `rkhunter --propupd` to re-baseline file properties — a MUTATING,
#:              gated operation that must only run on a host you know is clean.
#:              Installs nothing: gates on rkhunter/chkrootkit being present and
#:              points at linux-intrusion-detection for install steps.
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
UPDATE_BASELINE=0          # --update-baseline → run rkhunter --propupd (MUTATING)
QUICK=0                    # --quick → rkhunter only, skip chkrootkit
RKH_LOG="/var/log/rkhunter.log"

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-rootkit-scan [OPTIONS]

Run rkhunter and chkrootkit on Debian/Ubuntu and RHEL-family servers, then
summarise the warnings and highlight findings that warrant investigation.
Read-only by default — it scans and reports, it does not change the system,
EXCEPT under --update-baseline (see below).

This is a convenience wrapper. The scanners must already be installed; see
linux-intrusion-detection (references/rootkit-scanning.md) for install steps.

OPTIONS:
        --update-baseline   Run `rkhunter --propupd` to re-baseline file
                            properties. MUTATING and gated — only run on a host
                            you KNOW is clean (e.g. right after patching from
                            trusted repos). Refuses to auto-run under --yes
                            without confirmation.
        --quick             rkhunter only; skip the (slower) chkrootkit pass.

STANDARD FLAGS:
    -h, --help          Show this help and exit
        --version       Print version
    -y, --yes           Non-interactive mode
    -n, --dry-run       Print what would run, change nothing
        --log           Tee output to /var/log/linux-skills/
    -v, --verbose       Extra diagnostic output
    -q, --quiet         Errors and final result only

EXIT CODES:
    0  scan completed, no warnings surfaced
    1  scan completed, one or more warnings surfaced (investigate)
    2  usage / flag error
    3  precondition failed (not root, or unsupported distro)
    5  dependency missing (rkhunter / chkrootkit not installed)

EXAMPLES:
    sudo sk-rootkit-scan
    sudo sk-rootkit-scan --quick --log
    sudo sk-rootkit-scan --update-baseline      # after trusted patching only

NOTE:
    rkhunter and chkrootkit are heuristic. They produce false positives
    (package updates, legitimate hidden files, container/virtualisation
    artefacts). Treat every warning as "verify", never as "confirmed rootkit".
    Correlate with AIDE drift and auditd before declaring an incident.

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
        --update-baseline)
            UPDATE_BASELINE=1
            REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
            ;;
        --quick)
            QUICK=1
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
require_family any        # Debian/Ubuntu or RHEL family; sets SK_DISTRO_FAMILY

# At least rkhunter must be present. chkrootkit is optional (skipped in --quick).
if ! command -v rkhunter &>/dev/null && ! command -v chkrootkit &>/dev/null; then
    die "Neither rkhunter nor chkrootkit is installed. Install per linux-intrusion-detection/references/rootkit-scanning.md (apt install rkhunter chkrootkit / dnf install rkhunter chkrootkit)." 5
fi

# =============================================================================
# 6. Main logic
# =============================================================================
header "Rootkit scan — $(hostname) — $(date '+%Y-%m-%d %H:%M:%S')"
# shellcheck disable=SC1091
info "OS: $(. /etc/os-release && echo "$PRETTY_NAME") | family: $SK_DISTRO_FAMILY"

# --- Optional: re-baseline rkhunter file properties (MUTATING) ---------------
if (( UPDATE_BASELINE == 1 )); then
    if ! command -v rkhunter &>/dev/null; then
        die "--update-baseline requires rkhunter, which is not installed." 5
    fi
    header "Re-baseline rkhunter file properties (--propupd)"
    warn "This overwrites rkhunter's stored file-property baseline. Only proceed"
    warn "if this host is KNOWN-CLEAN (e.g. immediately after patching from"
    warn "trusted repositories). Re-baselining a compromised host hides the"
    warn "compromise."
    if [[ "$YES" == "1" ]]; then
        # Destructive-ish: never silently auto-run under --yes.
        confirm_destructive "Re-baseline rkhunter properties on $(hostname)" \
            || die "User aborted baseline update." 4
    else
        confirm "Re-baseline rkhunter file properties now?" \
            || die "User aborted baseline update." 4
    fi
    run rkhunter --propupd --nocolors
    pass "rkhunter baseline updated."
    info "Re-run a scan to confirm the warning count drops."
fi

# --- rkhunter scan -----------------------------------------------------------
RKH_WARN=0
if command -v rkhunter &>/dev/null; then
    header "rkhunter"
    # --check runs all tests; --sk skips the interactive keypress between groups;
    # --rwo prints "report warnings only"; --nocolors keeps the log clean.
    if (( DRY_RUN == 1 )); then
        run rkhunter --check --sk --nocolors --rwo
        info "(dry-run) rkhunter not executed."
    else
        # rkhunter exits non-zero when warnings are found; capture, don't abort.
        RKH_OUT="$(rkhunter --check --sk --nocolors --rwo 2>&1 || true)"
        if [[ -n "$RKH_OUT" ]]; then
            RKH_WARN=$(printf '%s\n' "$RKH_OUT" | grep -ci 'warning' || true)
            printf '%s\n' "$RKH_OUT" | sed 's/^/         /'
        fi
        if (( RKH_WARN > 0 )); then
            warn "rkhunter raised $RKH_WARN warning(s) — see $RKH_LOG for detail."
            info "Full log: less $RKH_LOG   (grep '\\[ Warning \\]' for the lines)"
        else
            pass "rkhunter: no warnings."
        fi
    fi
else
    info "rkhunter not installed — skipping (install per the reference)."
fi

# --- chkrootkit scan ---------------------------------------------------------
CHK_WARN=0
if (( QUICK == 1 )); then
    info "chkrootkit skipped (--quick)."
elif command -v chkrootkit &>/dev/null; then
    header "chkrootkit"
    if (( DRY_RUN == 1 )); then
        run chkrootkit -q
        info "(dry-run) chkrootkit not executed."
    else
        # -q = quiet: print only INFECTED / suspicious lines, not every "not found".
        CHK_OUT="$(chkrootkit -q 2>&1 || true)"
        if [[ -n "$CHK_OUT" ]]; then
            # Drop the well-known false-positive on the wtmp/'packet sniffer'
            # promiscuous-mode line so genuine hits stand out; still logged below.
            CHK_WARN=$(printf '%s\n' "$CHK_OUT" \
                | grep -ciE 'INFECTED|suspicious|vulnerable' || true)
            printf '%s\n' "$CHK_OUT" | sed 's/^/         /'
        fi
        if (( CHK_WARN > 0 )); then
            warn "chkrootkit flagged $CHK_WARN line(s) — verify each (false positives are common)."
        else
            pass "chkrootkit: nothing flagged."
        fi
    fi
else
    info "chkrootkit not installed — skipping (rkhunter alone ran)."
fi

# =============================================================================
# 7. Summary
# =============================================================================
header "Summary"
TOTAL=$(( RKH_WARN + CHK_WARN ))
if (( DRY_RUN == 1 )); then
    info "Dry-run complete — nothing was scanned or changed."
    exit 0
fi

if (( TOTAL == 0 )); then
    pass "No rootkit-scanner warnings on $(hostname)."
    info "Heuristic scanners: clean output is reassuring, not proof. Keep AIDE"
    info "and auditd running for drift and attribution."
    exit 0
fi

warn "$TOTAL scanner warning(s) total (rkhunter: $RKH_WARN, chkrootkit: $CHK_WARN)."
info "Triage: (1) check whether a recent package update explains it"
info "        (2) re-run after 'rkhunter --propupd' on a clean host to clear"
info "            benign property-change warnings"
info "        (3) cross-check flagged paths with AIDE (sk-file-integrity-check)"
info "            and auditd (ausearch -f <path>) before declaring an incident."
exit 1
