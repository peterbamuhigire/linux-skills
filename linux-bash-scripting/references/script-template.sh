#!/usr/bin/env bash
#: Title:       sk-example
#: Synopsis:    sk-example [--flags] <arg>
#: Description: One-line description of what this script does.
#: Author:      Peter Bamuhigire <techguypeter.com>
#: Contact:     +256784464178
#: Version:     0.1.0
#
# This is the canonical template every `sk-*` script in the linux-skills repo
# must start from. Copy it with `sk-new-script <skill> <name>`, then fill in
# the sections. Do not remove or reorder the sections.
#
# Read linux-bash-scripting/SKILL.md and docs/engine-design/spec.md before
# modifying this file.

# =============================================================================
# 1. Library + safety
# =============================================================================
set -uo pipefail

# In production the library is installed at this path:
SK_LIB="/usr/local/lib/linux-skills/common.sh"

# In development fall back to the repo copy:
if [[ ! -f "$SK_LIB" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SK_LIB="${SCRIPT_DIR}/lib/common.sh"
fi
# shellcheck source=/dev/null
source "$SK_LIB" || { echo "FATAL: cannot source common.sh from $SK_LIB" >&2; exit 5; }

# =============================================================================
# 2. Defaults (every tunable at the top)
# =============================================================================
SCRIPT_VERSION="0.1.0"
DOMAIN=""
PORT=443
CONFIG_PATH="/etc/example"

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-example [OPTIONS] <arg>

DESCRIPTION:
    One-line description of what this script does.

DECISION FLAGS (required under --yes):
    --domain <name>       Domain to operate on
    --port <n>            Port number (default: 443)
    --config <path>       Path to config (default: /etc/example)

STANDARD FLAGS:
    -h, --help            Show this help and exit
        --version         Print version and exit
    -y, --yes             Non-interactive mode. Errors if a required flag is
                          missing; never silently defaults.
    -n, --dry-run         Print every action; change nothing
        --log[=PATH]      Tee output to /var/log/linux-skills/<script>.log
        --json            Machine-readable output (no colors)
    -v, --verbose         Extra diagnostics
    -q, --quiet           Errors and final result only

EXIT CODES:
    0  success
    1  generic failure
    2  usage or flag error
    3  precondition failed
    4  user aborted
    5  dependency missing

EXAMPLES:
    sk-example --domain example.com
    sk-example --yes --domain example.com --port 443 --log

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
parse_standard_flags "$@"

# Parse script-specific decision flags from REMAINING_ARGS.
while [[ ${#REMAINING_ARGS[@]} -gt 0 ]]; do
    case "${REMAINING_ARGS[0]}" in
        --domain)
            DOMAIN="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --port)
            PORT="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --config)
            CONFIG_PATH="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --version)
            printf 'sk-example %s\n' "$SCRIPT_VERSION"
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: ${REMAINING_ARGS[0]}" 2
            ;;
    esac
done

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_root
require_debian
require_cmd nginx openssl

if [[ "$YES" == "1" ]]; then
    require_flag DOMAIN
fi

# Validate formats with case, not sprawling regex.
case "$DOMAIN" in
    "" )        : ;;   # empty is OK here; may be prompted below
    *.*.* )     : ;;
    *.* )       : ;;
    * )         die "Invalid --domain: '$DOMAIN' (expected a FQDN)" 2 ;;
esac

# =============================================================================
# 6. Main logic
# =============================================================================
header "sk-example — $(hostname)"

if [[ -z "$DOMAIN" ]]; then
    DOMAIN=$(prompt "Domain to operate on" "" 'case "$1" in *.*) return 0;; *) return 1;; esac')
fi

info "Domain: $DOMAIN"
info "Port:   $PORT"
info "Config: $CONFIG_PATH"

confirm_destructive "About to modify ${CONFIG_PATH} for ${DOMAIN}" \
    || die "User aborted" 4

# Example: atomic config write
TMP_CONFIG=$(safe_tempfile example-conf)
cat > "$TMP_CONFIG" <<EOF
# managed by sk-example
server_name $DOMAIN;
listen $PORT ssl;
EOF

backup_file "$CONFIG_PATH/site.conf"
run install -m 0644 -o root -g root "$TMP_CONFIG" "$CONFIG_PATH/site.conf"

# Validate before reload
run nginx -t || die "nginx config invalid — reverted" 1
run systemctl reload nginx

pass "Configuration applied for $DOMAIN"

# Final summary
printf '\n'
header "Summary"
printf '  PASS: %d  WARN: %d  FAIL: %d\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
exit 0
