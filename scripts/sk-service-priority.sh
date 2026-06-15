#!/usr/bin/env bash
#: Title:       sk-service-priority
#: Synopsis:    sk-service-priority <service> [--show|--cpu-weight N|--cpu-quota PCT|--io-weight N|--memory-max SIZE|--nice N] [--runtime]
#: Description: Inspect or set cgroup resource limits and scheduling priority
#:              for a systemd service on Debian/Ubuntu or the RHEL family
#:              (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). With no
#:              limit flags it SHOWS the effective CPUWeight/CPUQuota/IOWeight/
#:              MemoryMax/Nice and the live cgroup usage — read-only. With limit
#:              flags it applies them via `systemctl set-property` after asking
#:              for confirmation, so a background service cannot starve the host.
#:              systemd, cgroup v2, and set-property are identical across both
#:              families. See references/resource-control-and-targets.md.
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

SERVICE=""
RUNTIME=0
SET_CPU_WEIGHT=""
SET_CPU_QUOTA=""
SET_IO_WEIGHT=""
SET_MEMORY_MAX=""
SET_NICE=""

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-service-priority <service> [OPTIONS]

Inspect or set cgroup resource limits and scheduling priority for a systemd
service, on Debian/Ubuntu or the RHEL family (Fedora, RHEL, CentOS Stream,
Rocky, Alma, Oracle). systemd / cgroup v2 are identical on both.

With NO limit flags, this is READ-ONLY: it prints the effective CPUWeight,
CPUQuota, IOWeight, MemoryMax, and Nice for the service, plus a snapshot of
its live cgroup resource usage.

With one or more limit flags, it applies them via `systemctl set-property`
after asking you to confirm. Limits keep a background service from starving
the host. By default the change is persistent (a drop-in is written under
/etc/systemd/system/<unit>.d/); pass --runtime to apply only until reboot.

LIMIT FLAGS (any combination):
        --cpu-weight N      Relative CPU share, 1-10000 (default 100).
        --cpu-quota PCT     Hard CPU cap, e.g. 50% = half a core, 200% = 2 cores.
        --io-weight N       Relative block-I/O share, 1-10000 (needs bfq scheduler).
        --memory-max SIZE   Hard memory ceiling, e.g. 512M, 2G. OOM-kill past it.
        --nice N            CPU niceness, -20 (highest) .. 19 (lowest).
        --runtime           Apply only until next reboot (no drop-in written).
        --show              Force show-only (the default when no limit flag given).

STANDARD FLAGS:
    -h, --help              Show this help and exit
        --version           Print version
    -y, --yes               Non-interactive; auto-confirm the change
    -n, --dry-run           Print the set-property command, change nothing
        --log               Tee output to /var/log/linux-skills/
    -v, --verbose           Echo commands as they run
    -q, --quiet             Errors and result only

EXIT CODES:
    0  success
    1  generic failure
    2  usage/flag error
    3  precondition failed (not root for a mutation, or unsupported distro)
    5  dependency missing

EXAMPLES:
    sudo sk-service-priority nginx                         # show current limits
    sudo sk-service-priority reindexer --cpu-quota 50% --memory-max 512M
    sudo sk-service-priority mysql --io-weight 50 --runtime
    sudo sk-service-priority backup --nice 15 --cpu-weight 20

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# Print one effective property value for the unit.
show_prop() {
    local prop="$1"
    local val
    val="$(systemctl show "$SERVICE" -p "$prop" --value 2>/dev/null)"
    printf "  %-14s %s\n" "$prop:" "${val:-<unset>}"
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
# Pre-consume our custom flags, then hand the rest to parse_standard_flags.
ARGS=()
while (( $# > 0 )); do
    case "$1" in
        --cpu-weight)  SET_CPU_WEIGHT="${2:-}"; shift ;;
        --cpu-weight=*) SET_CPU_WEIGHT="${1#*=}" ;;
        --cpu-quota)   SET_CPU_QUOTA="${2:-}"; shift ;;
        --cpu-quota=*) SET_CPU_QUOTA="${1#*=}" ;;
        --io-weight)   SET_IO_WEIGHT="${2:-}"; shift ;;
        --io-weight=*) SET_IO_WEIGHT="${1#*=}" ;;
        --memory-max)  SET_MEMORY_MAX="${2:-}"; shift ;;
        --memory-max=*) SET_MEMORY_MAX="${1#*=}" ;;
        --nice)        SET_NICE="${2:-}"; shift ;;
        --nice=*)      SET_NICE="${1#*=}" ;;
        --runtime)     RUNTIME=1 ;;
        --show)        : ;;  # explicit; default behavior anyway
        *)             ARGS+=("$1") ;;
    esac
    shift
done
set -- "${ARGS[@]}"
parse_standard_flags "$@"

# First non-flag remaining arg is the service name.
if (( ${#REMAINING_ARGS[@]} > 0 )); then
    SERVICE="${REMAINING_ARGS[0]}"
fi

# =============================================================================
# 5. Sanity checks
# =============================================================================
[[ -z "$SERVICE" ]] && { usage; die "no service named" 2; }
require_cmd systemctl
require_family any        # Debian/Ubuntu or RHEL family

# Normalize logical names (apache->apache2/httpd, cron->crond, ssh->sshd).
SERVICE="$(svc_name "$SERVICE")"

# Append .service if the caller gave a bare name (leave .target/.socket/etc).
[[ "$SERVICE" == *.* ]] || SERVICE="${SERVICE}.service"

if ! systemctl cat "$SERVICE" >/dev/null 2>&1; then
    die "unit not found: $SERVICE" 2
fi

# Decide mode: any limit flag set => mutate, else show-only.
MUTATE=0
PROPS=()
[[ -n "$SET_CPU_WEIGHT" ]] && { PROPS+=("CPUWeight=$SET_CPU_WEIGHT"); MUTATE=1; }
[[ -n "$SET_CPU_QUOTA"  ]] && { PROPS+=("CPUQuota=$SET_CPU_QUOTA");   MUTATE=1; }
[[ -n "$SET_IO_WEIGHT"  ]] && { PROPS+=("IOWeight=$SET_IO_WEIGHT");   MUTATE=1; }
[[ -n "$SET_MEMORY_MAX" ]] && { PROPS+=("MemoryMax=$SET_MEMORY_MAX"); MUTATE=1; }
[[ -n "$SET_NICE"       ]] && { PROPS+=("Nice=$SET_NICE");            MUTATE=1; }

# =============================================================================
# 6. Main logic
# =============================================================================
header "Resource control: $SERVICE"

if (( MUTATE == 0 )); then
    # ----- SHOW (read-only) -----
    info "Effective resource limits (systemctl show):"
    show_prop CPUWeight
    show_prop CPUQuota
    show_prop CPUQuotaPerSecUSec
    show_prop IOWeight
    show_prop MemoryMax
    show_prop MemoryHigh
    show_prop Nice
    show_prop IOSchedulingClass
    show_prop TasksMax

    printf "\n"
    info "cgroup membership and live usage:"
    systemctl status "$SERVICE" --no-pager 2>/dev/null \
        | grep -E "CGroup:|Memory:|CPU:|Tasks:" \
        | while IFS= read -r line; do printf "  %s\n" "$line"; done

    printf "\n"
    info "Tip: pass --cpu-quota / --memory-max / --io-weight / --nice to enforce limits."
    info "Full directive reference: references/resource-control-and-targets.md"
    exit 0
fi

# ----- MUTATE (set-property) -----
require_root

SCOPE="persistent (drop-in written to /etc/systemd/system/${SERVICE}.d/)"
RUNTIME_FLAG=()
if (( RUNTIME == 1 )); then
    SCOPE="runtime only (reverts on reboot)"
    RUNTIME_FLAG=(--runtime)
fi

info "Will apply to ${SERVICE} [${SCOPE}]:"
for p in "${PROPS[@]}"; do
    printf "    %s\n" "$p"
done

if ! confirm "Apply these resource limits to ${SERVICE}?" "N"; then
    info "aborted by user"
    exit 0
fi

run systemctl set-property "${RUNTIME_FLAG[@]}" "$SERVICE" "${PROPS[@]}" \
    || die "systemctl set-property failed for $SERVICE" 1

_sk_audit "set-property $SERVICE ${PROPS[*]} (${SCOPE})"
pass "applied ${#PROPS[@]} property(ies) to $SERVICE"

# Confirm what stuck.
printf "\n"
info "Effective values now:"
[[ -n "$SET_CPU_WEIGHT" ]] && show_prop CPUWeight
[[ -n "$SET_CPU_QUOTA"  ]] && show_prop CPUQuota
[[ -n "$SET_IO_WEIGHT"  ]] && show_prop IOWeight
[[ -n "$SET_MEMORY_MAX" ]] && show_prop MemoryMax
[[ -n "$SET_NICE"       ]] && show_prop Nice

exit 0
