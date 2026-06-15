#!/usr/bin/env bash
#: Title:       sk-container-ps
#: Synopsis:    sk-container-ps [--all] [--log]
#: Description: Read-only view of running containers and how they are managed on
#:              Debian/Ubuntu and RHEL-family hosts. Lists Docker and/or Podman
#:              containers with image, status, restart policy and health; any
#:              compose projects; and systemd/Quadlet container units. Use it to
#:              answer "what containers are running and what keeps them running?"
#:              Non-destructive — observes only, never modifies.
#:              See references/compose-and-systemd-reference.md.
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
SHOW_ALL=0

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-container-ps [OPTIONS]

Read-only report of running containers (Docker and/or Podman) plus the systemd
and Quadlet units that supervise them. Works on Debian/Ubuntu and the RHEL
family; auto-detects via common.sh. Never modifies the system.

Reports:
  - Docker containers: name, image, status, restart policy, health
  - Podman containers: name, image, status
  - compose projects (docker compose ls)
  - systemd container/Quadlet units (container-*.service, *.container generated)

OPTIONS:
    -a, --all           Include stopped containers
STANDARD FLAGS:
    -h, --help          Show this help and exit
        --version       Print version
    -y, --yes           No-op (this script is already read-only)
    -n, --dry-run       No-op (this script is already read-only)
        --log           Tee output to /var/log/linux-skills/
    -v, --verbose       Extra diagnostic output
    -q, --quiet         Errors and final result only

EXIT CODES:
    0  success
    3  precondition failed (unsupported distro)
    5  dependency missing (neither docker nor podman installed)

EXAMPLES:
    sk-container-ps
    sk-container-ps --all
    sudo sk-container-ps --log

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
parse_standard_flags "$@"
for arg in "${REMAINING_ARGS[@]:-}"; do
    case "$arg" in
        -a|--all) SHOW_ALL=1 ;;
    esac
done

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_family any

HAVE_DOCKER=0
HAVE_PODMAN=0
command -v docker >/dev/null 2>&1 && HAVE_DOCKER=1
command -v podman >/dev/null 2>&1 && HAVE_PODMAN=1

if [[ "$HAVE_DOCKER" == "0" && "$HAVE_PODMAN" == "0" ]]; then
    die "no container engine found (neither 'docker' nor 'podman' installed)" 5
fi

PS_FLAGS=""
[[ "$SHOW_ALL" == "1" ]] && PS_FLAGS="-a"

# =============================================================================
# 6. Main logic
# =============================================================================

if [[ "$HAVE_DOCKER" == "1" ]]; then
    header "Docker containers"
    if docker ps $PS_FLAGS \
        --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null; then
        :
    else
        warn "could not query docker (daemon down or no permission)"
    fi

    if [[ "$VERBOSE" == "1" ]]; then
        info "restart policies:"
        for c in $(docker ps $PS_FLAGS --format '{{.Names}}' 2>/dev/null); do
            pol="$(docker inspect "$c" --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null)"
            info "  $c -> ${pol:-unknown}"
        done
    fi

    header "Docker compose projects"
    docker compose ls 2>/dev/null || info "no compose projects (or compose plugin absent)"
fi

if [[ "$HAVE_PODMAN" == "1" ]]; then
    header "Podman containers"
    podman ps $PS_FLAGS \
        --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null \
        || warn "could not query podman"
fi

header "Systemd / Quadlet container units"
if command -v systemctl >/dev/null 2>&1; then
    units="$(systemctl list-units --type=service --all --no-legend 2>/dev/null \
        | awk '{print $1}' | grep -E 'container-|^[a-z0-9_-]+\.service' \
        | grep -iE 'container|podman|quadlet' || true)"
    if [[ -n "$units" ]]; then
        printf '%s\n' "$units" | sed 's/^/  /'
    else
        info "no container systemd units found (system scope)"
    fi
    # Quadlet source files
    for qd in /etc/containers/systemd "$HOME/.config/containers/systemd"; do
        if [[ -d "$qd" ]]; then
            q="$(find "$qd" -maxdepth 1 -name '*.container' 2>/dev/null || true)"
            [[ -n "$q" ]] && info "Quadlet units in $qd:" && printf '%s\n' "$q" | sed 's/^/    /'
        fi
    done
else
    info "systemctl not available"
fi

header "Result"
pass "container deployment inspection complete (read-only)"
exit 0
