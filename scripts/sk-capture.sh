#!/usr/bin/env bash
#: Title:       sk-capture
#: Synopsis:    sk-capture [--iface IF] [--filter 'BPF'] [--count N] [--size MB]
#:                         [--files N] [--snaplen B] [--out FILE] [-y]
#: Description: Safe wrapper around `tcpdump -w` for capturing a bounded pcap on
#:              a production server. Always bounds the capture (packet count OR a
#:              size/file ring) so it can never fill the terminal or the disk,
#:              excludes the operator's own SSH session by default, and asks
#:              before it starts writing. Works on both families (Debian/Ubuntu
#:              and the RHEL family); tcpdump itself is family-agnostic. Read the
#:              capture back with `tcpdump -r FILE` or analyze it in
#:              Wireshark/tshark. See
#:              linux-troubleshooting/references/packet-capture-and-tracing.md.
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
IFACE="any"             # capture on all interfaces unless told otherwise
FILTER=""               # extra BPF expression (combined with the SSH exclusion)
COUNT=0                 # stop after N packets (0 = use the size/file ring instead)
SIZE_MB=100             # per-file size for the ring buffer (tcpdump -C)
FILES=10                # number of ring files to keep (tcpdump -W)
SNAPLEN=0               # bytes per packet (0 = full packet)
OUT=""                  # output pcap path (default chosen below)
NO_SSH_EXCLUDE=0        # by default exclude the operator's own SSH session

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-capture [OPTIONS]

Safely capture a bounded pcap with tcpdump. The capture is ALWAYS bounded so it
cannot run away: either by packet count (--count) or by a size/file ring
(--size + --files, the default). Asks before it starts writing.

Read the capture back with:   tcpdump -nn -r FILE
Analyze offline with:         tshark -r FILE -Y '<display filter>'   (or Wireshark)

OPTIONS:
        --iface IF      Interface to capture on. Default: any (all interfaces).
                        List with: tcpdump -D
        --filter 'BPF'  Extra BPF capture filter, e.g. 'host 10.0.0.5 and port 443'.
                        Quote it. Combined (AND) with the SSH-exclusion guard.
        --count N       Stop after N packets (bounded, single file). When set,
                        the size/file ring is not used.
        --size MB       Ring-buffer file size in MB (tcpdump -C). Default: 100.
        --files N       Ring-buffer file count (tcpdump -W). Default: 10.
                        Total disk use is bounded to roughly size*files MB.
        --snaplen B     Bytes captured per packet (tcpdump -s). 0 = full packet.
                        Use 96 for headers-only connection debugging.
        --out FILE      Output pcap path. Default: /var/log/linux-skills/
                        cap-<host>-<timestamp>.pcap
        --include-ssh   Do NOT exclude your own SSH session from the capture
                        (by default 'not port 22' is added to the filter).

STANDARD FLAGS:
    -h, --help          Show this help and exit
        --version       Print version
    -y, --yes           Non-interactive: auto-confirm the capture
    -n, --dry-run       Show the tcpdump command; capture nothing
        --log           Tee output to /var/log/linux-skills/
    -v, --verbose       Echo each command before running it
    -q, --quiet         Errors and final result only

EXIT CODES:
    0  success (capture completed or was declined)
    1  generic failure (tcpdump error)
    2  bad argument
    3  precondition failed (not root)
    5  dependency missing (tcpdump)

EXAMPLES:
    # Capture 200 packets on port 443 to the default file
    sudo sk-capture --filter 'port 443' --count 200

    # Headers-only ring buffer of MySQL traffic on eth0 (10x100MB files)
    sudo sk-capture --iface eth0 --filter 'tcp port 3306' --snaplen 96

    # Capture a specific client/SYN problem, full packets, to a named file
    sudo sk-capture --filter 'host 10.0.0.5 and tcp port 8080' \
                    --out /tmp/syn-debug.pcap --count 500

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
        --iface)        IFACE="${2:?--iface needs a value}"; shift ;;
        --iface=*)      IFACE="${1#*=}" ;;
        --filter)       FILTER="${2:?--filter needs a value}"; shift ;;
        --filter=*)     FILTER="${1#*=}" ;;
        --count)        COUNT="${2:?--count needs a value}"; shift ;;
        --count=*)      COUNT="${1#*=}" ;;
        --size)         SIZE_MB="${2:?--size needs a value}"; shift ;;
        --size=*)       SIZE_MB="${1#*=}" ;;
        --files)        FILES="${2:?--files needs a value}"; shift ;;
        --files=*)      FILES="${1#*=}" ;;
        --snaplen)      SNAPLEN="${2:?--snaplen needs a value}"; shift ;;
        --snaplen=*)    SNAPLEN="${1#*=}" ;;
        --out)          OUT="${2:?--out needs a value}"; shift ;;
        --out=*)        OUT="${1#*=}" ;;
        --include-ssh)  NO_SSH_EXCLUDE=1 ;;
        *)              die "unknown argument: $1 (see --help)" 2 ;;
    esac
    shift
done

# Validate numeric inputs
for pair in "COUNT:$COUNT" "SIZE_MB:$SIZE_MB" "FILES:$FILES" "SNAPLEN:$SNAPLEN"; do
    val="${pair#*:}"
    [[ "$val" =~ ^[0-9]+$ ]] || die "${pair%%:*} must be a non-negative integer (got '$val')" 2
done
(( SIZE_MB >= 1 )) || die "--size must be >= 1 MB" 2
(( FILES   >= 1 )) || die "--files must be >= 1" 2

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_root
require_cmd tcpdump

# Choose a default output path under the engine's log dir.
if [[ -z "$OUT" ]]; then
    install -d -m 0750 "$SK_AUDIT_DIR" 2>/dev/null || true
    OUT="${SK_AUDIT_DIR}/cap-$(hostname -s 2>/dev/null || echo host)-$(date +%Y%m%d-%H%M%S).pcap"
fi
OUT_DIR="$(dirname "$OUT")"
[[ -d "$OUT_DIR" ]] || die "output directory does not exist: $OUT_DIR" 2

# Warn if the chosen interface is not one tcpdump can see.
if [[ "$IFACE" != "any" ]] && ! tcpdump -D 2>/dev/null | grep -q "[0-9]\.$IFACE\b\|\b$IFACE\b"; then
    warn "interface '$IFACE' not in 'tcpdump -D' list — capture may produce nothing"
    info "available interfaces:"; tcpdump -D 2>/dev/null | sed 's/^/    /'
fi

# =============================================================================
# 6. Build the BPF filter
# =============================================================================
# By default exclude the operator's own SSH session so it does not flood the
# capture (and, when capturing remotely, feed back on itself).
EFFECTIVE_FILTER="$FILTER"
if [[ "$NO_SSH_EXCLUDE" != "1" ]]; then
    if [[ -n "$EFFECTIVE_FILTER" ]]; then
        EFFECTIVE_FILTER="($EFFECTIVE_FILTER) and not port 22"
    else
        EFFECTIVE_FILTER="not port 22"
    fi
fi

# =============================================================================
# 7. Assemble the tcpdump command
# =============================================================================
CMD=(tcpdump -i "$IFACE" -nn -w "$OUT" -s "$SNAPLEN")
BOUND_DESC=""
if (( COUNT > 0 )); then
    CMD+=(-c "$COUNT")
    BOUND_DESC="stop after ${COUNT} packets → single file ${OUT}"
else
    # Size/file ring buffer: bounds total disk use to ~SIZE_MB*FILES.
    CMD+=(-C "$SIZE_MB" -W "$FILES")
    BOUND_DESC="ring buffer: ${FILES} files × ${SIZE_MB} MB (max ~$((SIZE_MB * FILES)) MB) at ${OUT}*"
fi
# The BPF filter must be the trailing args, split into words.
read -r -a FILTER_ARGS <<< "$EFFECTIVE_FILTER"
CMD+=("${FILTER_ARGS[@]}")

# =============================================================================
# 8. Confirm, then capture
# =============================================================================
header "Capture plan"
info "Interface : $IFACE"
info "Filter    : ${EFFECTIVE_FILTER:-<none>}"
info "Snaplen   : $( (( SNAPLEN == 0 )) && echo 'full packet' || echo "${SNAPLEN} bytes" )"
info "Bound     : $BOUND_DESC"
info "Command   : ${CMD[*]}"

if [[ "$DRY_RUN" == "1" ]]; then
    info "[dry-run] would run the command above; nothing written."
    print_summary
    exit 0
fi

if ! confirm "Start this capture now? (writes pcap to $OUT_DIR)" "N"; then
    info "Capture declined. Nothing written."
    print_summary
    exit 0
fi

_sk_audit "starting capture: ${CMD[*]}"
header "Capturing — press Ctrl-C to stop"
if run "${CMD[@]}"; then
    pass "Capture complete."
else
    rc=$?
    # tcpdump returns non-zero when interrupted by Ctrl-C, which is normal here.
    if (( rc == 130 )); then
        pass "Capture stopped by operator (Ctrl-C)."
    else
        fail "tcpdump exited with status $rc"
    fi
fi

info "Read it back:   tcpdump -nn -r ${OUT}"
info "Analyze:        tshark -r ${OUT} -Y '<display filter>'   (or open in Wireshark)"
_sk_audit "capture finished: $OUT"

# =============================================================================
# Summary
# =============================================================================
print_summary
exit 0
