#!/usr/bin/env bash
#: Title:       sk-sysctl-tune
#: Synopsis:    sk-sysctl-tune [--show|--profile web|throughput|balanced] [--apply] [--file PATH]
#: Description: Inspect or apply PERFORMANCE-oriented kernel tunables via sysctl
#:              on Debian/Ubuntu or the RHEL family (Fedora, RHEL, CentOS Stream,
#:              Rocky, Alma, Oracle). sysctl, /etc/sysctl.d, and `sysctl --system`
#:              are identical across both families. With no flags (or --show) it
#:              is READ-ONLY: it prints the current live value of every tunable
#:              in the chosen profile alongside the value the profile would set.
#:              With --apply it writes a profile to a drop-in under
#:              /etc/sysctl.d/ and runs `sysctl --system`, after asking to
#:              confirm. Dry-run-aware (--dry-run prints the file + command and
#:              changes nothing). This is PERFORMANCE tuning only; security
#:              sysctl lives in linux-server-hardening. See
#:              references/sysctl-tuning-reference.md.
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

PROFILE="balanced"
APPLY=0
DROPIN="/etc/sysctl.d/60-linux-skills-perf.conf"

# =============================================================================
# 3. Profiles — PERFORMANCE tunables only (NOT security; see linux-server-hardening)
# =============================================================================
# Each profile is a newline-separated list of "key = value" pairs.

profile_throughput() {
    cat <<'EOF'
# 10GbE+ high-throughput networking
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.netdev_max_backlog = 250000
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_mtu_probing = 1
EOF
}

profile_web() {
    cat <<'EOF'
# Connection-scaling web/proxy server
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
vm.swappiness = 10
EOF
}

profile_balanced() {
    cat <<'EOF'
# Sensible general-server defaults
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5
vm.overcommit_memory = 0
EOF
}

emit_profile() {
    case "$PROFILE" in
        throughput) profile_throughput ;;
        web)        profile_web ;;
        balanced)   profile_balanced ;;
        *) die "unknown profile: $PROFILE (use throughput|web|balanced)" 2 ;;
    esac
}

# =============================================================================
# 4. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-sysctl-tune [OPTIONS]

Inspect or apply PERFORMANCE kernel tunables via sysctl, on Debian/Ubuntu or
the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). sysctl and
/etc/sysctl.d are identical on both families.

With NO flags (or --show) this is READ-ONLY: it prints, for the chosen profile,
the LIVE value of each tunable next to the value the profile would set, so you
can review the delta before changing anything.

With --apply it writes the profile to a drop-in under /etc/sysctl.d/ and runs
`sysctl --system`, after asking you to confirm.

This is PERFORMANCE tuning only (throughput, connection scaling, memory). For
SECURITY sysctl (rp_filter, syncookies, kptr_restrict, ...) use the
linux-server-hardening skill instead.

OPTIONS:
        --profile NAME      throughput | web | balanced (default: balanced)
        --apply             Write drop-in + run `sysctl --system` (mutating)
        --show              Force show-only (default when --apply absent)
        --file PATH         Drop-in path (default /etc/sysctl.d/60-linux-skills-perf.conf)

STANDARD FLAGS:
    -h, --help              Show this help and exit
        --version           Print version
    -y, --yes               Non-interactive; auto-confirm the apply
    -n, --dry-run           Print the drop-in + commands, change nothing
        --log               Tee output to /var/log/linux-skills/
    -v, --verbose           Echo commands as they run
    -q, --quiet             Errors and result only

EXIT CODES:
    0  success
    1  generic failure
    2  usage/flag error
    3  precondition failed (not root for --apply, or unsupported distro)
    5  dependency missing

EXAMPLES:
    sk-sysctl-tune                                  # show balanced delta (read-only)
    sk-sysctl-tune --profile throughput             # show 10GbE delta
    sudo sk-sysctl-tune --profile web --apply       # write drop-in + sysctl --system
    sudo sk-sysctl-tune --profile throughput --apply --dry-run

NOTE on BBR: tcp_congestion_control=bbr needs the bbr module / kernel support.
The script verifies bbr is available before writing it; on older kernels it
warns and you should pick `cubic` (the safe default) instead.

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# Read the live value of a sysctl key (dotted form).
live_val() {
    local key="$1"
    sysctl -n "$key" 2>/dev/null || echo "<unset>"
}

# =============================================================================
# 5. Flag parsing
# =============================================================================
ARGS=()
while (( $# > 0 )); do
    case "$1" in
        --profile)   PROFILE="${2:-}"; shift ;;
        --profile=*) PROFILE="${1#*=}" ;;
        --file)      DROPIN="${2:-}"; shift ;;
        --file=*)    DROPIN="${1#*=}" ;;
        --apply)     APPLY=1 ;;
        --show)      : ;;  # explicit; default
        *)           ARGS+=("$1") ;;
    esac
    shift
done
set -- "${ARGS[@]}"
parse_standard_flags "$@"

# =============================================================================
# 6. Sanity checks
# =============================================================================
require_cmd sysctl
require_family any        # Debian/Ubuntu or RHEL family

# Validate profile early.
emit_profile >/dev/null

# =============================================================================
# 7. Main logic
# =============================================================================
header "sysctl performance tuning — profile: $PROFILE"

# Detect BBR availability (informational; affects the warning, not the file).
BBR_OK=0
if sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
    BBR_OK=1
elif modprobe -n tcp_bbr 2>/dev/null; then
    BBR_OK=1
fi

# ----- SHOW (read-only): print live vs desired -----
info "Current live value vs profile target (review before --apply):"
printf "  %-42s %-22s %s\n" "KEY" "LIVE" "PROFILE"
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    key="${line%%=*}"; key="${key// /}"
    want="${line#*=}"; want="${want# }"
    printf "  %-42s %-22s %s\n" "$key" "$(live_val "$key")" "$want"
done < <(emit_profile)

if grep -qw bbr <(emit_profile); then
    if (( BBR_OK == 0 )); then
        warn "tcp_congestion_control=bbr requested but bbr not available on this kernel."
        warn "Load it (modprobe tcp_bbr) or switch this profile's value to 'cubic'."
    fi
fi

if (( APPLY == 0 )); then
    printf "\n"
    info "Read-only. Re-run with --apply (as root) to write $DROPIN and run 'sysctl --system'."
    info "Full reference: references/sysctl-tuning-reference.md"
    exit 0
fi

# ----- APPLY (mutating) -----
require_root

info "Will write the $PROFILE profile to: $DROPIN"
info "Then run: sysctl --system"

if ! confirm "Write drop-in and apply with 'sysctl --system'?" "N"; then
    info "aborted by user"
    exit 0
fi

CONTENT="$(printf '# Managed by linux-skills sk-sysctl-tune (profile: %s)\n# %s\n%s\n' \
    "$PROFILE" "$(date -Iseconds)" "$(emit_profile)")"

if [[ "$DRY_RUN" == "1" ]]; then
    info "[dry-run] would write to $DROPIN:"
    printf '%s\n' "$CONTENT" | sed 's/^/    /'
    info "[dry-run] would run: sysctl --system"
    exit 0
fi

printf '%s\n' "$CONTENT" > "$DROPIN" || die "failed to write $DROPIN" 1
chmod 0644 "$DROPIN"
_sk_audit "wrote sysctl drop-in $DROPIN (profile $PROFILE)"
pass "wrote $DROPIN"

run sysctl --system >/dev/null || die "sysctl --system failed" 1
_sk_audit "applied sysctl --system"
pass "applied with 'sysctl --system'"

printf "\n"
info "Effective values now:"
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    key="${line%%=*}"; key="${key// /}"
    printf "  %-42s %s\n" "$key" "$(live_val "$key")"
done < <(emit_profile)

exit 0
