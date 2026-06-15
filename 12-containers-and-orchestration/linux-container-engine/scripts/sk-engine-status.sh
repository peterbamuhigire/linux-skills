#!/usr/bin/env bash
#: Title:       sk-engine-status
#: Synopsis:    sk-engine-status [--log]
#: Description: Read-only inventory of the container engine layer on Debian/Ubuntu
#:              and RHEL-family hosts. Detects the Docker daemon and/or Podman,
#:              and reports version, storage driver, default network bridge,
#:              configured registries, and key hardening flags (userns-remap,
#:              no-new-privileges, docker.sock permissions, who is in the docker
#:              group). Non-destructive — observes only, never modifies.
#:              See references/container-engine-reference.md.
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

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-engine-status [OPTIONS]

Read-only report of the installed container engine(s): Docker daemon and/or
Podman. Works on Debian/Ubuntu and the RHEL family; auto-detects via common.sh.
Never modifies the system.

Reports:
  - which engine(s) are present (docker daemon, podman)
  - engine version and storage driver
  - default network bridge / backend
  - configured registries (daemon.json mirrors, registries.conf)
  - hardening flags: userns-remap, no-new-privileges, docker.sock perms,
    docker group membership

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
    sk-engine-status
    sudo sk-engine-status --log

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
parse_standard_flags "$@"

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_family any        # Debian/Ubuntu or RHEL family; sets SK_DISTRO_FAMILY

HAVE_DOCKER=0
HAVE_PODMAN=0
command -v docker >/dev/null 2>&1 && HAVE_DOCKER=1
command -v podman >/dev/null 2>&1 && HAVE_PODMAN=1

if [[ "$HAVE_DOCKER" == "0" && "$HAVE_PODMAN" == "0" ]]; then
    die "no container engine found (neither 'docker' nor 'podman' installed)" 5
fi

# =============================================================================
# 6. Main logic
# =============================================================================

header "Engine detection"
[[ "$HAVE_DOCKER" == "1" ]] && pass "docker CLI present" || info "docker not installed"
[[ "$HAVE_PODMAN" == "1" ]] && pass "podman present (daemonless)" || info "podman not installed"

if [[ "$HAVE_DOCKER" == "1" ]]; then
    header "Docker daemon"
    if systemctl is-active --quiet docker 2>/dev/null; then
        pass "docker.service is active"
    else
        warn "docker.service is not active (daemon down or rootless-only)"
    fi
    docker version --format 'client {{.Client.Version}} / server {{.Server.Version}}' 2>/dev/null \
        | sed 's/^/  /' || warn "could not query docker version (daemon unreachable?)"

    info "storage driver: $(docker info --format '{{.Driver}}' 2>/dev/null || echo unknown)"
    info "security options: $(docker info --format '{{.SecurityOptions}}' 2>/dev/null || echo unknown)"

    # userns-remap and no-new-privileges from daemon.json
    if [[ -f /etc/docker/daemon.json ]]; then
        info "daemon.json present: /etc/docker/daemon.json"
        grep -q 'userns-remap' /etc/docker/daemon.json 2>/dev/null \
            && pass "userns-remap configured in daemon.json" \
            || warn "userns-remap NOT set in daemon.json"
        grep -q 'no-new-privileges' /etc/docker/daemon.json 2>/dev/null \
            && pass "no-new-privileges configured in daemon.json" \
            || warn "no-new-privileges NOT set in daemon.json"
        if [[ "$VERBOSE" == "1" ]]; then
            info "registry-mirrors:"
            grep -A3 'registry-mirrors' /etc/docker/daemon.json 2>/dev/null | sed 's/^/    /' || true
        fi
    else
        warn "no /etc/docker/daemon.json — daemon running on defaults"
    fi

    header "Docker socket & group"
    if [[ -S /var/run/docker.sock ]]; then
        info "socket perms: $(stat -c '%A %U:%G' /var/run/docker.sock 2>/dev/null)"
    fi
    if getent group docker >/dev/null 2>&1; then
        info "docker group members: $(getent group docker | cut -d: -f4)"
        warn "docker group membership is root-equivalent — audit the list above"
    fi

    if [[ "$VERBOSE" == "1" ]]; then
        info "default bridge subnet:"
        docker network inspect bridge --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null \
            | sed 's/^/    /' || true
    fi
fi

if [[ "$HAVE_PODMAN" == "1" ]]; then
    header "Podman"
    podman version --format '{{.Version}}' 2>/dev/null | sed 's/^/  version /' || true
    info "storage driver: $(podman info --format '{{.Store.GraphDriverName}}' 2>/dev/null || echo unknown)"
    info "rootless: $(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null || echo unknown)"

    for rc in /etc/containers/registries.conf "$HOME/.config/containers/registries.conf"; do
        if [[ -f "$rc" ]]; then
            pass "registries config present: $rc"
            if grep -q 'unqualified-search-registries' "$rc" 2>/dev/null; then
                info "unqualified-search-registries set ($rc)"
            else
                warn "no unqualified-search-registries in $rc — bare 'podman pull' is ambiguous"
            fi
        fi
    done

    if [[ "$VERBOSE" == "1" ]]; then
        info "podman networks:"
        podman network ls 2>/dev/null | sed 's/^/    /' || true
    fi
fi

header "Result"
pass "container engine inspection complete (read-only)"
exit 0
