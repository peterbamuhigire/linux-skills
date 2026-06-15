#!/usr/bin/env bash
#: Title:       sk-mysql-health
#: Synopsis:    sk-mysql-health [--defaults-file <path>] [--json]
#: Description: Read-only health check for MySQL/MariaDB on both families.
#:              Reports connectivity, uptime/qps, thread count vs max_connections,
#:              InnoDB buffer-pool hit ratio, binary-logging state, and slow-query
#:              count. Non-destructive — never mutates the server. PASS/WARN/FAIL.
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
DEFAULTS_FILE="${MYSQL_DEFAULTS_FILE:-}"

usage() {
    cat <<'EOF'
Usage: sk-mysql-health [OPTIONS]

Read-only health check for MySQL/MariaDB. Reports connectivity, uptime/qps,
connection headroom, InnoDB buffer-pool hit ratio, binary-logging state, and
slow-query count. Never modifies the server.

OPTIONS:
        --defaults-file <path>  MySQL client config (user/password/socket).
                                Defaults to socket auth (sudo) if omitted.
    -h, --help                  Show this help and exit
        --version               Print version
        --json                  (reserved) machine-readable output
    -q, --quiet                 Errors and result only

EXIT CODES:
    0  all checks passed (no FAIL)
    1  one or more checks failed
    3  cannot connect to the server
    5  mysql client not installed

EXAMPLES:
    sudo sk-mysql-health
    sk-mysql-health --defaults-file ~/.my.cnf

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# =============================================================================
# 3. Flag parsing
# =============================================================================
parse_standard_flags "$@"

while (( ${#REMAINING_ARGS[@]} > 0 )); do
    case "${REMAINING_ARGS[0]}" in
        --defaults-file)
            DEFAULTS_FILE="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        *)
            die "unknown argument: ${REMAINING_ARGS[0]}" 2
            ;;
    esac
done

# =============================================================================
# 4. Sanity checks
# =============================================================================
require_family any
require_cmd mysql

MYSQL=(mysql)
[[ -n "$DEFAULTS_FILE" ]] && MYSQL=(mysql --defaults-file="$DEFAULTS_FILE")

# A single scalar from SHOW STATUS / SHOW VARIABLES (column 2 of a -N row).
sval() {
    "${MYSQL[@]}" -N -e "$1" 2>/dev/null | awk '{print $2}'
}

# =============================================================================
# 5. Main logic
# =============================================================================
header "sk-mysql-health — $(hostname)"

if ! "${MYSQL[@]}" -N -e "SELECT 1;" >/dev/null 2>&1; then
    die "cannot connect to MySQL/MariaDB (try sudo, or pass --defaults-file)" 3
fi
pass "connected to server"

VERSION="$("${MYSQL[@]}" -N -e "SELECT VERSION();" 2>/dev/null)"
info "version: ${VERSION:-unknown}"

# --- Uptime / qps ------------------------------------------------------------
UPTIME="$(sval "SHOW GLOBAL STATUS LIKE 'Uptime';")"
QUESTIONS="$(sval "SHOW GLOBAL STATUS LIKE 'Questions';")"
if [[ -n "${UPTIME:-}" && "${UPTIME:-0}" -gt 0 ]]; then
    QPS=$(( ${QUESTIONS:-0} / UPTIME ))
    info "uptime: ${UPTIME}s, ~${QPS} queries/s"
fi

# --- Connection headroom -----------------------------------------------------
MAXCONN="$(sval "SHOW VARIABLES LIKE 'max_connections';")"
MAXUSED="$(sval "SHOW GLOBAL STATUS LIKE 'Max_used_connections';")"
CONNNOW="$(sval "SHOW GLOBAL STATUS LIKE 'Threads_connected';")"
info "connections: ${CONNNOW:-?} now, ${MAXUSED:-?} peak, ${MAXCONN:-?} max"
if [[ -n "${MAXCONN:-}" && -n "${MAXUSED:-}" && "${MAXCONN:-0}" -gt 0 ]]; then
    PCT=$(( ${MAXUSED:-0} * 100 / MAXCONN ))
    if (( PCT >= 90 )); then
        fail "peak connections at ${PCT}% of max_connections — raise it or add pooling"
    elif (( PCT >= 75 )); then
        warn "peak connections at ${PCT}% of max_connections"
    else
        pass "connection headroom healthy (${PCT}% peak)"
    fi
fi

# --- InnoDB buffer-pool hit ratio -------------------------------------------
READS="$(sval "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_reads';")"
REQS="$(sval "SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read_requests';")"
if [[ -n "${REQS:-}" && "${REQS:-0}" -gt 0 ]]; then
    # hit ratio = (requests - disk reads) / requests * 100
    HIT=$(( ( REQS - ${READS:-0} ) * 100 / REQS ))
    if (( HIT >= 99 )); then
        pass "InnoDB buffer-pool hit ratio ${HIT}%"
    elif (( HIT >= 95 )); then
        warn "InnoDB buffer-pool hit ratio ${HIT}% — consider larger innodb_buffer_pool_size"
    else
        fail "InnoDB buffer-pool hit ratio ${HIT}% — buffer pool likely undersized"
    fi
else
    info "InnoDB buffer-pool stats unavailable"
fi

# --- Binary logging ----------------------------------------------------------
LOGBIN="$(sval "SHOW VARIABLES LIKE 'log_bin';")"
if [[ "${LOGBIN:-OFF}" == "ON" ]]; then
    pass "binary logging enabled (PITR possible)"
else
    warn "binary logging OFF — point-in-time recovery not available"
fi

# --- Slow queries ------------------------------------------------------------
SLOW="$(sval "SHOW GLOBAL STATUS LIKE 'Slow_queries';")"
if [[ -n "${SLOW:-}" ]]; then
    if (( SLOW > 0 )); then
        warn "${SLOW} slow queries since start — review the slow query log"
    else
        pass "no slow queries recorded"
    fi
fi

print_summary
(( FAIL_COUNT == 0 )) || exit 1
exit 0
