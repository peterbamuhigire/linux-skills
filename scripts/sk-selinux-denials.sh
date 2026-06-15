#!/usr/bin/env bash
#: Title:       sk-selinux-denials
#: Synopsis:    sk-selinux-denials [--since recent|today|boot] [--module NAME] [-y]
#: Description: Triage SELinux AVC denials on the RHEL family (Fedora, RHEL,
#:              CentOS Stream, Rocky, Alma, Oracle). Summarizes recent denials,
#:              runs audit2why for a plain-English rationale, and — ONLY after
#:              you confirm — builds a local policy module with audit2allow,
#:              shows the generated .te for review, and (on a second confirm)
#:              installs it with semodule. Never disables SELinux and never
#:              calls setenforce. RHEL-family only; the Debian/Ubuntu MAC
#:              counterpart is AppArmor (aa-logprof). See
#:              linux-server-hardening/references/selinux-reference.md.
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
SINCE="recent"          # ausearch -ts value: recent|today|boot|HH:MM:SS
MODULE_NAME="sk_local_pol"

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-selinux-denials [OPTIONS]

Triage SELinux AVC denials and optionally build a reviewed local policy module.
RHEL family only (SELinux). Never disables SELinux; never calls setenforce.

What it does:
  1. Summarizes recent AVC denials (ausearch + aureport --avc).
  2. Runs audit2why for a plain-English rationale.
  3. Reminds you to prefer a context/boolean/port fix first.
  4. ONLY on confirmation: builds a local module with audit2allow, prints the
     generated .te for review, and on a SECOND confirmation installs it with
     semodule.

OPTIONS:
        --since VALUE   Time window for ausearch -ts (recent|today|boot|HH:MM:SS).
                        Default: recent (~last 10 minutes).
        --module NAME   Name for the generated policy module. Default: sk_local_pol.

STANDARD FLAGS:
    -h, --help          Show this help and exit
        --version       Print version
    -y, --yes           Non-interactive: auto-confirm (still REVIEW the .te in logs)
    -n, --dry-run       Show what would run; build nothing, install nothing
        --log           Tee output to /var/log/linux-skills/
    -v, --verbose       Echo each command before running it
    -q, --quiet         Errors and final result only

EXIT CODES:
    0  success (triage completed)
    1  generic failure
    3  precondition failed (not root, not RHEL family, or SELinux disabled)
    5  dependency missing (policycoreutils-python-utils / audit)

EXAMPLES:
    sudo sk-selinux-denials                       # triage last ~10 min
    sudo sk-selinux-denials --since today
    sudo sk-selinux-denials --since boot --module my_httpd

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
parse_standard_flags "$@"
set -- "${REMAINING_ARGS[@]}"
while (( $# > 0 )); do
    case "$1" in
        --since)   SINCE="${2:?--since needs a value}"; shift ;;
        --since=*) SINCE="${1#*=}" ;;
        --module)  MODULE_NAME="${2:?--module needs a value}"; shift ;;
        --module=*) MODULE_NAME="${1#*=}" ;;
        *)         die "unknown argument: $1 (see --help)" 2 ;;
    esac
    shift
done

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_root
require_family rhel       # SELinux is the RHEL-family MAC; Debian/Ubuntu use AppArmor
require_cmd ausearch audit2why audit2allow getenforce semodule

MODE="$(getenforce 2>/dev/null || echo Unknown)"
if [[ "$MODE" == "Disabled" ]]; then
    die "SELinux is Disabled — there are no AVC denials to triage. Re-enable it (SELINUX=enforcing in /etc/selinux/config) before troubleshooting." 3
fi
info "SELinux mode: $MODE  (this tool never changes the mode)"

# =============================================================================
# 6. Main logic
# =============================================================================

# --- Step 1: summarize denials ----------------------------------------------
header "1. Recent AVC denials (since: $SINCE)"
AVC_RAW="$(ausearch -m AVC,USER_AVC -ts "$SINCE" 2>/dev/null)"
if [[ -z "$AVC_RAW" ]]; then
    pass "No AVC denials found in window '$SINCE' — nothing to triage."
    info "Widen the window with --since today or --since boot if you expected some."
    print_summary
    exit 0
fi
DENIAL_COUNT="$(printf '%s\n' "$AVC_RAW" | grep -c 'avc:  *denied' || true)"
warn "$DENIAL_COUNT AVC denial record(s) in window '$SINCE'"
printf '%s\n' "$AVC_RAW" | grep 'avc:  *denied' | tail -20

header "AVC summary (aureport)"
if command -v aureport >/dev/null 2>&1; then
    aureport --avc 2>/dev/null | tail -20 || true
fi

# --- Step 2: audit2why rationale --------------------------------------------
header "2. Why were these denied? (audit2why)"
printf '%s\n' "$AVC_RAW" | audit2why 2>/dev/null || warn "audit2why produced no output"

# --- Step 3: nudge toward the right fix -------------------------------------
header "3. Preferred fixes (try these BEFORE a policy module)"
info "Wrong file label?  semanage fcontext -a -t <type> \"<path>(/.*)?\"  &&  restorecon -Rv <path>"
info "Capability toggle? setsebool -P <boolean> on   (e.g. httpd_can_network_connect)"
info "Non-standard port? semanage port -a -t <type> -p tcp <port>"
info "Per-domain relax?  semanage permissive -a <domain_t>   (NOT setenforce 0)"
info "Full guidance: linux-server-hardening/references/selinux-reference.md"

# --- Step 4: optional local policy module (last resort) ---------------------
header "4. Build a local policy module (last resort)"
if ! confirm "Build a local policy module from these denials with audit2allow?" "N"; then
    info "Skipped module generation. Prefer a context/boolean/port fix above."
    print_summary
    exit 0
fi

if [[ "$DRY_RUN" == "1" ]]; then
    info "[dry-run] would run: ausearch -m AVC -ts $SINCE | audit2allow -M $MODULE_NAME"
    info "[dry-run] would then show ${MODULE_NAME}.te for review and ask before semodule -i"
    print_summary
    exit 0
fi

WORKDIR="$(safe_tempdir sk-selinux)"
( cd "$WORKDIR" && printf '%s\n' "$AVC_RAW" | audit2allow -M "$MODULE_NAME" ) \
    || die "audit2allow failed to build module '$MODULE_NAME'" 1

TE_FILE="${WORKDIR}/${MODULE_NAME}.te"
PP_FILE="${WORKDIR}/${MODULE_NAME}.pp"
[[ -f "$PP_FILE" ]] || die "expected compiled module $PP_FILE not found" 1

header "Generated policy — REVIEW every 'allow' line before installing"
if [[ -f "$TE_FILE" ]]; then
    cat "$TE_FILE"
    _sk_audit "generated module $MODULE_NAME; .te contents reviewed by operator"
fi

printf '\n'
if confirm_destructive "Install module '$MODULE_NAME' with 'semodule -i'? Only do this if every allow rule above is acceptable."; then
    run semodule -i "$PP_FILE" || die "semodule -i failed" 1
    pass "Installed local policy module: $MODULE_NAME"
    info "Verify: semodule -l | grep $MODULE_NAME    |    Remove: sudo semodule -r $MODULE_NAME"
    _sk_audit "installed semodule $MODULE_NAME"
else
    info "Did not install. The reviewed .te is at: $TE_FILE (removed on exit unless copied out)."
    warn "Re-run after applying a context/boolean/port fix if that is the cleaner solution."
fi

# =============================================================================
# Summary
# =============================================================================
print_summary
exit 0
