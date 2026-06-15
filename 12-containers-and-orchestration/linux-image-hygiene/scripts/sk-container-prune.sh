#!/usr/bin/env bash
#: Title:       sk-container-prune
#: Synopsis:    sk-container-prune [--scope safe|images|aggressive] [--install-timer] [--schedule-safe]
#: Description: Reclaim container disk on Debian/Ubuntu and RHEL-family hosts.
#:              Reports reclaimable space (system df), then prunes Docker and/or
#:              Podman at a chosen scope, asking before each destructive step.
#:              Can install a daily systemd timer that runs a conservative prune.
#:              Follows the common.sh contract: ask before mutating, --dry-run,
#:              --yes for automation. See references/prune-and-scheduling.md.
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
SCOPE="safe"              # safe | images | aggressive
INSTALL_TIMER=0
SCHEDULE_SAFE=0           # internal: invoked from the timer for an unattended safe prune
PRUNE_TIMER_NAME="container-prune"

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-container-prune [OPTIONS]

Reclaim container disk: report reclaimable space, then prune Docker and/or
Podman at a chosen scope. Works on Debian/Ubuntu and the RHEL family.

SCOPES (--scope):
    safe         dangling images + stopped containers + unused networks + cache
                 (this is `system prune`, NO -a, NO --volumes) [default]
    images       safe + all unused images (`image prune -a`)
    aggressive   everything unused INCLUDING named volumes (DESTRUCTIVE)

OPTIONS:
        --scope SCOPE       Prune scope (safe|images|aggressive). Default: safe
        --install-timer     Install a daily systemd timer running a safe prune
        --schedule-safe     Run one unattended safe prune (used by the timer)
STANDARD FLAGS:
    -h, --help              Show this help and exit
        --version           Print version
    -y, --yes               Auto-confirm (required for unattended/automation)
    -n, --dry-run           Show what would run, change nothing
        --log               Tee output to /var/log/linux-skills/
    -v, --verbose           Extra diagnostic output
    -q, --quiet             Errors and final result only

EXIT CODES:
    0  success
    2  bad usage (unknown scope)
    3  precondition failed (not root, unsupported distro)
    5  dependency missing (neither docker nor podman installed)

EXAMPLES:
    sudo sk-container-prune                      # report + safe prune (asks first)
    sudo sk-container-prune --scope images
    sudo sk-container-prune --scope aggressive --dry-run
    sudo sk-container-prune --install-timer      # daily 03:30 safe prune
    sudo sk-container-prune --schedule-safe --yes  # what the timer calls

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# Run a prune command on whichever engines are present.
prune_engines() {
    local label="$1"; shift          # remaining args = the prune verb + flags
    local engine
    for engine in docker podman; do
        command -v "$engine" >/dev/null 2>&1 || continue
        # docker needs a live daemon; skip if unreachable
        if [[ "$engine" == "docker" ]] && ! docker info >/dev/null 2>&1; then
            info "docker daemon unreachable — skipping docker $label"
            continue
        fi
        info "$engine: $label"
        run "$engine" "$@"
    done
}

install_timer() {
    require_root
    local svc="/etc/systemd/system/${PRUNE_TIMER_NAME}.service"
    local tmr="/etc/systemd/system/${PRUNE_TIMER_NAME}.timer"
    local self="/usr/local/bin/${SK_SCRIPT_NAME}"
    [[ -x "$self" ]] || self="$(command -v "$SK_SCRIPT_NAME" || echo "$self")"

    info "installing systemd prune timer ($tmr)"
    run bash -c "cat > '$svc'" <<EOF
[Unit]
Description=Scheduled container image/cache prune (linux-skills)
Documentation=man:docker-system-prune(1)

[Service]
Type=oneshot
ExecStart=${self} --schedule-safe --yes
EOF

    run bash -c "cat > '$tmr'" <<EOF
[Unit]
Description=Run container prune daily (linux-skills)

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    run systemctl daemon-reload
    run systemctl enable --now "${PRUNE_TIMER_NAME}.timer"
    pass "timer installed; next run:"
    systemctl list-timers "${PRUNE_TIMER_NAME}.timer" --no-pager 2>/dev/null | sed 's/^/  /' || true
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
parse_standard_flags "$@"
i=0
args=("${REMAINING_ARGS[@]:-}")
while (( i < ${#args[@]} )); do
    case "${args[$i]}" in
        --scope)         i=$((i+1)); SCOPE="${args[$i]:-}" ;;
        --scope=*)       SCOPE="${args[$i]#*=}" ;;
        --install-timer) INSTALL_TIMER=1 ;;
        --schedule-safe) SCHEDULE_SAFE=1 ;;
    esac
    i=$((i+1))
done

case "$SCOPE" in
    safe|images|aggressive) ;;
    *) die "unknown --scope '$SCOPE' (use safe|images|aggressive)" 2 ;;
esac

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_root
require_family any

if ! command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
    die "no container engine found (neither 'docker' nor 'podman' installed)" 5
fi

# =============================================================================
# 6. Main logic
# =============================================================================

if [[ "$INSTALL_TIMER" == "1" ]]; then
    install_timer
    header "Result"
    pass "prune timer installed"
    exit 0
fi

# Unattended path used by the timer: always a safe prune, no prompts.
if [[ "$SCHEDULE_SAFE" == "1" ]]; then
    SCOPE="safe"
    YES=1
fi

header "Reclaimable space (before)"
for engine in docker podman; do
    command -v "$engine" >/dev/null 2>&1 || continue
    if [[ "$engine" == "docker" ]] && ! docker info >/dev/null 2>&1; then continue; fi
    info "$engine system df:"
    "$engine" system df 2>/dev/null | sed 's/^/    /' || warn "$engine system df failed"
done

header "Prune (scope: $SCOPE)"
case "$SCOPE" in
    safe)
        if confirm "Prune stopped containers, dangling images, unused networks and build cache?" Y; then
            prune_engines "system prune (safe)" system prune -f
        else
            info "skipped"
        fi
        ;;
    images)
        if confirm "Prune all UNUSED images plus the safe set?" N; then
            prune_engines "system prune (safe)" system prune -f
            prune_engines "image prune -a"      image  prune -a -f
        else
            info "skipped"
        fi
        ;;
    aggressive)
        warn "aggressive scope removes UNUSED VOLUMES — data in orphaned volumes is lost"
        if confirm_destructive "Prune EVERYTHING unused, including named volumes?"; then
            prune_engines "system prune -a --volumes" system prune -a --volumes -f
        else
            info "aborted"
            exit 0
        fi
        ;;
esac

header "Reclaimable space (after)"
for engine in docker podman; do
    command -v "$engine" >/dev/null 2>&1 || continue
    if [[ "$engine" == "docker" ]] && ! docker info >/dev/null 2>&1; then continue; fi
    "$engine" system df 2>/dev/null | sed 's/^/    /' || true
done

header "Result"
pass "container prune complete (scope: $SCOPE)"
exit 0
