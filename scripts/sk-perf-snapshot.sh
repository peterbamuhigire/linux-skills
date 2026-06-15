#!/usr/bin/env bash
#: Title:       sk-perf-snapshot
#: Synopsis:    sk-perf-snapshot [--duration SEC] [--no-perf]
#: Description: Read-only quick-profile snapshot for finding CPU / I/O / memory
#:              bottlenecks on Debian/Ubuntu or the RHEL family (Fedora, RHEL,
#:              CentOS Stream, Rocky, Alma, Oracle). Captures a short window of
#:              vmstat, iostat -x (await/%util), mpstat (per-CPU), pidstat (top
#:              consumers), load average, and the top processes by CPU and by
#:              memory, then prints a one-line verdict (CPU-bound vs I/O-wait
#:              vs memory pressure). PURELY READ-ONLY — collects, never mutates.
#:              The sysstat tools (iostat/mpstat/pidstat/sar) ship in the
#:              `sysstat` package on both families; the script degrades
#:              gracefully if any are missing. See
#:              references/profiling-tools.md.
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

DURATION=3      # sampling window in seconds
USE_PERF=1

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-perf-snapshot [OPTIONS]

Read-only quick-profile snapshot of CPU / I/O / memory pressure, on
Debian/Ubuntu or the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma,
Oracle). Captures a short sampling window and prints a verdict. Never mutates.

Collects: uptime/load, vmstat, iostat -x (await + %util), mpstat (per-CPU),
pidstat (per-process CPU/IO), top processes by %CPU and %MEM, and — when
`perf` is present and you did not pass --no-perf — a 1-second `perf stat`.

The sysstat tools (iostat, mpstat, pidstat, sar) come from the `sysstat`
package: `apt install sysstat` / `dnf install sysstat`. Missing tools are
skipped with a note rather than failing.

OPTIONS:
        --duration SEC      Sampling window in seconds (default 3)
        --no-perf           Skip the perf stat step even if perf is installed

STANDARD FLAGS:
    -h, --help              Show this help and exit
        --version           Print version
        --log               Tee output to /var/log/linux-skills/
    -v, --verbose           Echo commands as they run
    -q, --quiet             Errors and result only

EXIT CODES:
    0  success
    2  usage/flag error
    3  unsupported distro

EXAMPLES:
    sk-perf-snapshot                    # 3-second snapshot + verdict
    sk-perf-snapshot --duration 10      # longer window for bursty load
    sk-perf-snapshot --no-perf          # skip perf stat

This is a triage snapshot. For sustained CPU profiling use `perf record`/
`perf report`; for historical trends use `sar`. See
references/profiling-tools.md.

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

# =============================================================================
# 4. Flag parsing
# =============================================================================
ARGS=()
while (( $# > 0 )); do
    case "$1" in
        --duration)   DURATION="${2:-}"; shift ;;
        --duration=*) DURATION="${1#*=}" ;;
        --no-perf)    USE_PERF=0 ;;
        *)            ARGS+=("$1") ;;
    esac
    shift
done
set -- "${ARGS[@]}"
parse_standard_flags "$@"

[[ "$DURATION" =~ ^[0-9]+$ && "$DURATION" -ge 1 ]] || die "--duration must be a positive integer" 2

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_family any        # Debian/Ubuntu or RHEL family

# =============================================================================
# 6. Main logic — collect only, never mutate
# =============================================================================
header "Performance snapshot (${DURATION}s window)"

info "Load average / uptime:"
uptime | sed 's/^/    /'

printf "\n"
info "Memory (free -h):"
free -h | sed 's/^/    /'

printf "\n"
info "vmstat (2 samples, ${DURATION}s apart) — watch 'wa' (I/O wait), 'r' (run queue), 'si/so' (swap):"
if have vmstat; then
    run vmstat "$DURATION" 2 | sed 's/^/    /'
else
    warn "vmstat not found (install procps / procps-ng)"
fi

printf "\n"
info "iostat -x — per-device await (ms) and %util; high %util + high await = disk bottleneck:"
if have iostat; then
    run iostat -x "$DURATION" 2 | sed 's/^/    /'
else
    warn "iostat not found (install sysstat)"
fi

printf "\n"
info "mpstat -P ALL — per-CPU breakdown; high %iowait or one hot core = imbalance:"
if have mpstat; then
    run mpstat -P ALL 1 "$DURATION" | tail -n +4 | sed 's/^/    /'
else
    warn "mpstat not found (install sysstat)"
fi

printf "\n"
info "pidstat — top processes by CPU and I/O over the window:"
if have pidstat; then
    run pidstat -u 1 "$DURATION" | tail -n +4 | sort -k8 -rn 2>/dev/null | head -6 | sed 's/^/    /'
else
    warn "pidstat not found (install sysstat)"
fi

printf "\n"
info "Top 5 by %CPU:"
ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -6 | sed 's/^/    /'

printf "\n"
info "Top 5 by %MEM:"
ps -eo pid,comm,%cpu,%mem --sort=-%mem 2>/dev/null | head -6 | sed 's/^/    /'

if (( USE_PERF == 1 )) && have perf; then
    printf "\n"
    info "perf stat (1s, system-wide) — IPC, cache-misses, context-switches:"
    run perf stat -a sleep 1 2>&1 | sed 's/^/    /' || warn "perf stat needs root / perf_event_paranoid access"
elif (( USE_PERF == 1 )); then
    printf "\n"
    info "perf not installed — skipping perf stat (install linux-tools-\$(uname -r) / perf)."
fi

# ----- Verdict: cheap heuristic from a fresh vmstat sample -----
printf "\n"
header "Verdict"
if have vmstat; then
    read -r _ _ _ _ _ _ _ _ _ _ _ _ _ WA _ < <(vmstat 1 2 | tail -1)
    read -r R _ < <(vmstat 1 2 | tail -1)
    WA="${WA:-0}"; R="${R:-0}"
    if [[ "$WA" =~ ^[0-9]+$ ]] && (( WA >= 20 )); then
        warn "High I/O wait (wa=${WA}%). Disk is the likely bottleneck — inspect iostat await/%util above."
    elif [[ "$R" =~ ^[0-9]+$ ]] && (( R > $(nproc) )); then
        warn "Run queue (r=${R}) exceeds CPU count ($(nproc)). CPU-bound — profile with 'perf top' / 'perf record'."
    else
        pass "No obvious CPU or I/O-wait bottleneck in this window."
    fi
else
    info "Install procps + sysstat for an automated verdict."
fi

info "Deeper analysis: references/profiling-tools.md"
exit 0
