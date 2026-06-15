#!/usr/bin/env bash
#: Title:       sk-benchmark-scan
#: Synopsis:    sk-benchmark-scan [--profile cis|stig|pci-dss|standard] [--lynis] [--no-oscap] [--outdir DIR]
#: Description: Read-only security-benchmark scan on Debian/Ubuntu and RHEL-family
#:              (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) servers. Auto-
#:              detects the distro/version, locates the matching SCAP Security
#:              Guide datastream, runs `oscap xccdf eval` against the chosen
#:              profile into a timestamped results.xml + report.html, and
#:              optionally runs `lynis audit system`. SCANS AND REPORTS ONLY — it
#:              never remediates and changes nothing on the host. Generating and
#:              applying remediation is a deliberate, separate step documented in
#:              linux-benchmark-scanning/references/openscap-reference.md.
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
PROFILE="cis"              # --profile: cis | stig | pci-dss | standard (suffix)
RUN_OSCAP=1               # --no-oscap disables
RUN_LYNIS=0               # --lynis enables
OUTDIR=""                 # --outdir; default chosen after flag parse
SSG_DIR="/usr/share/xml/scap/ssg/content"

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-benchmark-scan [OPTIONS]

Read-only benchmark/compliance scan on Debian/Ubuntu and RHEL-family servers.
Auto-detects the distro/version, finds the matching SCAP Security Guide
datastream, runs OpenSCAP against the chosen profile, and (optionally) Lynis.

SCANS AND REPORTS ONLY. It never remediates and changes nothing on the host.
To generate/apply remediation, follow openscap-reference.md deliberately.

OPTIONS:
        --profile NAME   SSG profile suffix to evaluate. One of:
                         cis | stig | pci-dss | hipaa | standard (default: cis).
                         The exact ID is resolved via `oscap info`; if not found
                         the script lists the available profiles and exits.
        --lynis          Also run `lynis audit system` (quick hardening index).
        --no-oscap       Skip the OpenSCAP scan (e.g. with --lynis for Lynis only).
        --outdir DIR     Where to write results.xml / report.html
                         (default: /var/log/linux-skills/benchmark-<timestamp>).

STANDARD FLAGS:
    -h, --help           Show this help and exit
        --version        Print version
    -y, --yes            Non-interactive mode
    -n, --dry-run        Print what would run, change nothing
        --log            Tee output to /var/log/linux-skills/
    -v, --verbose        Extra diagnostic output
    -q, --quiet          Errors and final result only

EXIT CODES:
    0  scan(s) completed
    2  usage / flag error
    3  precondition failed (not root, or unsupported distro)
    5  dependency missing (oscap/lynis or SSG content not installed)

EXAMPLES:
    sudo sk-benchmark-scan                          # CIS scan with OpenSCAP
    sudo sk-benchmark-scan --profile stig --lynis   # STIG + Lynis
    sudo sk-benchmark-scan --no-oscap --lynis       # Lynis only

NOTE:
    A passing scan means the baseline is met, not that the host is secure.
    Match the datastream to the distro/version (handled automatically). Review
    every generated remediation on a test host before production.

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# Map a friendly profile name to the SSG profile-ID suffix candidates.
profile_candidates() {
    case "$1" in
        cis)        printf '%s\n' cis cis_server_l1 cis_workstation_l1 ;;
        stig)       printf '%s\n' stig stig_gui ;;
        pci-dss)    printf '%s\n' pci-dss pci-dss-3.2.1 ;;
        hipaa)      printf '%s\n' hipaa ;;
        standard)   printf '%s\n' standard ospp ;;
        *)          printf '%s\n' "$1" ;;
    esac
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
parse_standard_flags "$@"

while [[ ${#REMAINING_ARGS[@]} -gt 0 ]]; do
    case "${REMAINING_ARGS[0]}" in
        --profile)
            PROFILE="${REMAINING_ARGS[1]:-}"
            [[ -z "$PROFILE" ]] && die "--profile needs a value (see --help)" 2
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --profile=*)
            PROFILE="${REMAINING_ARGS[0]#*=}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
            ;;
        --lynis)
            RUN_LYNIS=1
            REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
            ;;
        --no-oscap)
            RUN_OSCAP=0
            REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
            ;;
        --outdir)
            OUTDIR="${REMAINING_ARGS[1]:-}"
            [[ -z "$OUTDIR" ]] && die "--outdir needs a value (see --help)" 2
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --outdir=*)
            OUTDIR="${REMAINING_ARGS[0]#*=}"
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
require_family any        # Debian/Ubuntu or RHEL family; sets SK_DISTRO_*

if (( RUN_OSCAP == 0 && RUN_LYNIS == 0 )); then
    die "--no-oscap with no --lynis leaves nothing to do." 2
fi

TS="$(date +%Y%m%d-%H%M%S)"
if [[ -z "$OUTDIR" ]]; then
    OUTDIR="/var/log/linux-skills/benchmark-${TS}"
fi

# =============================================================================
# 6. Main logic
# =============================================================================
header "Benchmark scan — $(hostname) — $(date '+%Y-%m-%d %H:%M:%S')"
# shellcheck disable=SC1091
info "OS: $(. /etc/os-release && echo "$PRETTY_NAME") | family: $SK_DISTRO_FAMILY"
info "Output dir: $OUTDIR (read-only scan — nothing on the host is modified)"
run mkdir -p "$OUTDIR"

# --- OpenSCAP ----------------------------------------------------------------
if (( RUN_OSCAP == 1 )); then
    header "OpenSCAP (oscap xccdf eval)"
    if ! command -v oscap >/dev/null 2>&1; then
        warn "oscap not installed. Install: (RHEL) dnf install openscap-scanner scap-security-guide"
        warn "                              (Debian) apt install openscap-scanner ssg-debderived"
        info "See linux-benchmark-scanning/references/openscap-reference.md"
        if (( RUN_LYNIS == 0 )); then
            die "oscap missing and no other scanner requested." 5
        fi
    else
        # Resolve the datastream for this distro/version.
        # shellcheck disable=SC1091
        VID="$(. /etc/os-release && printf '%s' "${VERSION_ID:-}")"
        VMAJ="${VID%%.*}"
        DS=""
        # Try the most specific name first, then progressively looser globs.
        for cand in \
            "${SK_DISTRO_ID}${VMAJ}" \
            "${SK_DISTRO_ID}${VID}" \
            "${SK_DISTRO_ID}"; do
            match="$(ls "${SSG_DIR}/ssg-${cand}"*-ds.xml 2>/dev/null | head -1)"
            if [[ -n "$match" ]]; then DS="$match"; break; fi
        done

        if [[ -z "$DS" ]]; then
            warn "No SCAP Security Guide datastream found in ${SSG_DIR} for ${SK_DISTRO_ID} ${VID}."
            info "Available datastreams:"
            ls "${SSG_DIR}"/ssg-*-ds.xml 2>/dev/null | sed 's/^/         /' || info "  (none installed)"
            info "Install the SSG content package for this distro/version, then re-run."
            (( RUN_LYNIS == 1 )) || die "no datastream available." 5
        else
            info "Datastream: $DS"

            # Resolve the profile suffix to a full ID via `oscap info`.
            PROFILE_ID=""
            INFO="$(oscap info "$DS" 2>/dev/null || true)"
            while IFS= read -r sfx; do
                pid="$(printf '%s\n' "$INFO" \
                    | grep -oE 'xccdf_org\.ssgproject\.content_profile_[A-Za-z0-9_.-]+' \
                    | grep -E "_profile_${sfx}\$" | head -1 || true)"
                if [[ -n "$pid" ]]; then PROFILE_ID="$pid"; break; fi
            done < <(profile_candidates "$PROFILE")

            if [[ -z "$PROFILE_ID" ]]; then
                warn "Profile '$PROFILE' not found in $DS. Available profiles:"
                printf '%s\n' "$INFO" \
                    | grep -oE 'xccdf_org\.ssgproject\.content_profile_[A-Za-z0-9_.-]+' \
                    | sort -u | sed 's/^/         /'
                (( RUN_LYNIS == 1 )) || die "requested profile unavailable." 5
            else
                info "Profile: $PROFILE_ID"
                RES="${OUTDIR}/results.xml"
                REP="${OUTDIR}/report.html"
                # oscap exits non-zero when rules fail — that is normal; don't abort.
                run oscap xccdf eval \
                    --profile "$PROFILE_ID" \
                    --results "$RES" \
                    --report "$REP" \
                    "$DS" || true
                if (( DRY_RUN == 0 )) && [[ -f "$RES" ]]; then
                    # Count pass/fail from the results XML (rule-result elements).
                    P="$(grep -c '<result>pass</result>' "$RES" 2>/dev/null || true)"
                    F="$(grep -c '<result>fail</result>' "$RES" 2>/dev/null || true)"
                    pass "OpenSCAP complete: $P passed, $F failed."
                    info "Report:  $REP"
                    info "Results: $RES"
                    (( ${F:-0} > 0 )) && warn "$F rule(s) failed — review $REP and remediate on a test host first."
                else
                    info "(dry-run) oscap not executed."
                fi
            fi
        fi
    fi
fi

# --- Lynis -------------------------------------------------------------------
if (( RUN_LYNIS == 1 )); then
    header "Lynis (lynis audit system)"
    if ! command -v lynis >/dev/null 2>&1; then
        warn "lynis not installed. Install: apt install lynis  /  dnf install lynis (EPEL on RHEL/Rocky/Alma)."
        info "See linux-benchmark-scanning/references/lynis-reference.md"
    else
        LYNIS_LOG="${OUTDIR}/lynis.log"
        run lynis audit system --quiet --cronjob --logfile "$LYNIS_LOG" || true
        if (( DRY_RUN == 0 )) && [[ -f /var/log/lynis-report.dat ]]; then
            IDX="$(grep -E '^hardening_index=' /var/log/lynis-report.dat 2>/dev/null | tail -1 | cut -d= -f2 || true)"
            WC="$(grep -cE '^warning\[\]=' /var/log/lynis-report.dat 2>/dev/null || true)"
            SC="$(grep -cE '^suggestion\[\]=' /var/log/lynis-report.dat 2>/dev/null || true)"
            pass "Lynis complete: hardening index ${IDX:-n/a}, ${WC:-0} warning(s), ${SC:-0} suggestion(s)."
            info "Log: $LYNIS_LOG  |  report data: /var/log/lynis-report.dat"
        else
            info "(dry-run) lynis not executed."
        fi
    fi
fi

# =============================================================================
# 7. Summary
# =============================================================================
header "Summary"
if (( DRY_RUN == 1 )); then
    info "Dry-run complete — nothing was scanned or changed."
    exit 0
fi
info "Scan artefacts in: $OUTDIR"
info "This was a read-only scan. Remediation is a deliberate, separate step —"
info "see linux-benchmark-scanning/references/openscap-reference.md."
exit 0
