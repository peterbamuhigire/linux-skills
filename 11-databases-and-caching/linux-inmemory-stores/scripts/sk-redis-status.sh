#!/usr/bin/env bash
#: Title:       sk-redis-status
#: Synopsis:    sk-redis-status [-h <host>] [-p <port>] [-a <password>] [--log] [--json]
#: Description: Read-only Redis status report. Queries `redis-cli INFO` for memory
#:              (used / maxmemory / policy / evicted keys), persistence (RDB last
#:              save, AOF state) and client/connection counts, and inspects the
#:              bind address + requirepass. Flags a hard FAIL when Redis is bound
#:              to 0.0.0.0 with no password. Non-destructive — observes only.
#:              Runs on Debian/Ubuntu and the RHEL family.
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
    SK_LIB="${_SD}/../../../scripts/lib/common.sh"
fi
# shellcheck source=/dev/null
source "$SK_LIB" || { echo "FATAL: cannot source common.sh" >&2; exit 5; }

# =============================================================================
# 2. Defaults
# =============================================================================
SCRIPT_VERSION="0.1.0"
RHOST="127.0.0.1"
RPORT="6379"
RPASS=""

usage() {
    cat <<'EOF'
Usage: sk-redis-status [OPTIONS]

Read-only Redis status: memory/eviction, persistence, clients, and an
exposure check (bound to 0.0.0.0 with no password = FAIL). Non-destructive.

Options:
  -h <host>      Redis host (default 127.0.0.1)
  -p <port>      Redis port (default 6379)
  -a <password>  AUTH password (prefer linux-secrets; avoid on shared hosts)
  --log <file>   Append the report to a log file
  --json         Machine-readable mode (suppresses color)
  --help         Show this help
EOF
}

# =============================================================================
# 3. Argument parsing
# =============================================================================
PRE_ARGS=()
while (( $# )); do
    case "$1" in
        -h) RHOST="${2:-}"; shift 2 ;;
        -p) RPORT="${2:-}"; shift 2 ;;
        -a) RPASS="${2:-}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) PRE_ARGS+=("$1"); shift ;;
    esac
done
set -- "${PRE_ARGS[@]:-}"
parse_standard_flags "$@"

# =============================================================================
# 4. Dependencies
# =============================================================================
require_cmd redis-cli

# redis-cli invocation honoring optional host/port/auth.
rcli() {
    if [[ -n "$RPASS" ]]; then
        redis-cli -h "$RHOST" -p "$RPORT" -a "$RPASS" --no-auth-warning "$@"
    else
        redis-cli -h "$RHOST" -p "$RPORT" "$@"
    fi
}

# Pull a single field from `INFO` output (CRLF-terminated key:value lines).
info_field() {
    # info_field <section> <key>
    rcli INFO "$1" 2>/dev/null | tr -d '\r' | awk -F: -v k="$2" '$1==k {print $2; exit}'
}

# =============================================================================
# 5. Report
# =============================================================================
header "Redis status: ${RHOST}:${RPORT}"

if ! rcli PING 2>/dev/null | grep -q PONG; then
    fail "cannot reach Redis at ${RHOST}:${RPORT} (or AUTH required — pass -a)"
    print_summary
    exit 1
fi
pass "reachable (PONG)"

# --- Memory & eviction ---
header "Memory & eviction"
used="$(info_field memory used_memory_human)"
maxmem="$(info_field memory maxmemory_human)"
policy="$(info_field memory maxmemory_policy)"
evicted="$(info_field stats evicted_keys)"
info "used_memory: ${used:-?}"
if [[ -z "$maxmem" || "$maxmem" == "0B" || "$maxmem" == "0" ]]; then
    warn "maxmemory is unset (0) — Redis can consume all RAM and be OOM-killed"
else
    pass "maxmemory: ${maxmem}"
fi
info "maxmemory-policy: ${policy:-?}"
if [[ -n "$evicted" && "$evicted" != "0" ]]; then
    warn "evicted_keys=${evicted} — working set may exceed maxmemory"
else
    pass "evicted_keys: ${evicted:-0}"
fi

# --- Persistence ---
header "Persistence"
aof="$(info_field persistence aof_enabled)"
rdb_status="$(info_field persistence rdb_last_bgsave_status)"
rdb_changes="$(info_field persistence rdb_changes_since_last_save)"
if [[ "$aof" == "1" ]]; then
    pass "AOF enabled"
else
    info "AOF disabled"
fi
info "RDB last-bgsave status: ${rdb_status:-?}, changes since save: ${rdb_changes:-?}"
if [[ "$aof" != "1" && ( -z "$rdb_changes" ) ]]; then
    warn "no persistence detected — data will not survive a restart (cache mode)"
fi

# --- Clients ---
header "Clients"
clients="$(info_field clients connected_clients)"
maxclients="$(rcli CONFIG GET maxclients 2>/dev/null | tr -d '\r' | tail -1)"
info "connected_clients: ${clients:-?} (maxclients: ${maxclients:-?})"

# --- Exposure check ---
header "Network exposure"
bind="$(rcli CONFIG GET bind 2>/dev/null | tr -d '\r' | tail -1)"
protected="$(rcli CONFIG GET protected-mode 2>/dev/null | tr -d '\r' | tail -1)"
requirepass="$(rcli CONFIG GET requirepass 2>/dev/null | tr -d '\r' | tail -1)"
info "bind: ${bind:-<unset>}  protected-mode: ${protected:-?}"

has_pass=0
[[ -n "$requirepass" ]] && has_pass=1

exposed=0
# Empty bind, or a bind that includes 0.0.0.0 / ::, means all interfaces.
if [[ -z "$bind" || "$bind" == *"0.0.0.0"* || "$bind" == *"::"* ]]; then
    exposed=1
fi

if (( exposed == 1 )) && (( has_pass == 0 )) && [[ "$protected" != "yes" ]]; then
    fail "Redis bound to all interfaces with NO password and protected-mode off — remotely exploitable. Set requirepass (see linux-secrets) and firewall the port (linux-firewall-ssl)."
elif (( exposed == 1 )) && (( has_pass == 0 )); then
    warn "Redis reachable on all interfaces with no requirepass; protected-mode=${protected}. Set a password (linux-secrets) and restrict the port (linux-firewall-ssl)."
elif (( exposed == 1 )); then
    pass "bound to all interfaces but requirepass is set"
else
    pass "bound to a restricted interface (${bind})"
fi

print_summary
(( FAIL_COUNT == 0 ))
