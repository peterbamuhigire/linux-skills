#!/usr/bin/env bash
#: Title:       common.sh
#: Synopsis:    source /usr/local/lib/linux-skills/common.sh
#: Description: Shared library for every sk-* script in the linux-skills engine.
#:              Provides output primitives, guards, interaction helpers, safe file
#:              operations, standard flag parsing, and a cleanup trap. Read the
#:              contract at linux-bash-scripting/references/common-sh-contract.md
#:              before modifying any function in this file — scripts depend on
#:              the documented behavior.
#: Author:      Peter Bamuhigire <techguypeter.com>
#: Contact:     +256784464178
#: Version:     0.1.0

# shellcheck shell=bash

# Guard against double sourcing
if [[ -n "${SK_COMMON_LOADED:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi
SK_COMMON_LOADED=1

# =============================================================================
# Globals
# =============================================================================

# Script name (basename of the caller) — used in error messages and audit logs
SK_SCRIPT_NAME="$(basename "${BASH_SOURCE[1]:-$0}" .sh)"

# Standard flag state — parse_standard_flags sets these
DRY_RUN=0
YES=0
LOG_FILE=""
JSON=0
VERBOSE=0
QUIET=0
REMAINING_ARGS=()

# Counters for PASS/WARN/FAIL reports
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

# Audit log path (always written for destructive ops, regardless of --log)
SK_AUDIT_DIR="/var/log/linux-skills"
SK_AUDIT_LOG="${SK_AUDIT_DIR}/${SK_SCRIPT_NAME}.log"

# Cleanup registry — populated by safe_tempfile/safe_tempdir/sk_on_exit
SK_CLEANUP_PATHS=()
SK_CLEANUP_FUNCS=()

# =============================================================================
# Colors — collapse to empty strings when output is not a TTY, or under --json
# or --quiet. Initialized lazily after flag parsing.
# =============================================================================

SK_GREEN='' SK_YELLOW='' SK_RED='' SK_CYAN='' SK_BOLD='' SK_NC=''

_sk_init_colors() {
    if [[ "$JSON" == "1" || "$QUIET" == "1" ]] || [[ ! -t 1 ]]; then
        SK_GREEN='' SK_YELLOW='' SK_RED='' SK_CYAN='' SK_BOLD='' SK_NC=''
    else
        SK_GREEN='\033[0;32m'
        SK_YELLOW='\033[1;33m'
        SK_RED='\033[0;31m'
        SK_CYAN='\033[0;36m'
        SK_BOLD='\033[1m'
        SK_NC='\033[0m'
    fi
}
_sk_init_colors

# =============================================================================
# Output primitives
# =============================================================================

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    [[ "$QUIET" == "1" ]] && return 0
    printf "  ${SK_GREEN}[PASS]${SK_NC} %s\n" "$*"
    _sk_log_append "[PASS] $*"
}

warn() {
    WARN_COUNT=$((WARN_COUNT + 1))
    printf "  ${SK_YELLOW}[WARN]${SK_NC} %s\n" "$*"
    _sk_log_append "[WARN] $*"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf "  ${SK_RED}[FAIL]${SK_NC} %s\n" "$*"
    _sk_log_append "[FAIL] $*"
}

info() {
    [[ "$QUIET" == "1" ]] && return 0
    printf "  ${SK_CYAN}[INFO]${SK_NC} %s\n" "$*"
    _sk_log_append "[INFO] $*"
}

header() {
    [[ "$QUIET" == "1" ]] && return 0
    printf "\n${SK_BOLD}=== %s ===${SK_NC}\n" "$*"
    _sk_log_append "=== $* ==="
}

die() {
    local msg="$1"
    local code="${2:-1}"
    printf "${SK_RED}FATAL:${SK_NC} %s\n" "$msg" >&2
    _sk_log_append "FATAL: $msg (exit $code)"
    exit "$code"
}

log() {
    # Timestamped line to $LOG_FILE (if --log was passed). Used for narration
    # that should go to the log but not clutter stdout.
    [[ -z "$LOG_FILE" ]] && return 0
    printf '%s %s\n' "$(date -Iseconds)" "$*" >> "$LOG_FILE"
}

_sk_log_append() {
    # Append to $LOG_FILE if set, never fails
    [[ -n "$LOG_FILE" ]] && printf '%s %s\n' "$(date -Iseconds)" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

# =============================================================================
# Guards
# =============================================================================

require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "must run as root — try: sudo $SK_SCRIPT_NAME $*" 1
    fi
}

require_debian() {
    if [[ ! -f /etc/os-release ]]; then
        die "this script requires /etc/os-release (Debian/Ubuntu); not found" 3
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
        ubuntu|debian) return 0 ;;
        *)
            die "this script targets Ubuntu/Debian; detected: ${PRETTY_NAME:-unknown}" 3
            ;;
    esac
}

require_cmd() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        fail "missing required command(s): ${missing[*]}"
        info "install with: sudo apt install ${missing[*]}"
        die "dependency missing" 5
    fi
}

require_flag() {
    # Under --yes, aborts if the named variable is empty.
    # Use: require_flag DOMAIN (checks $DOMAIN).
    local var="$1"
    if [[ "$YES" == "1" && -z "${!var:-}" ]]; then
        die "--yes was passed but --${var,,} is required. Run with --help to see required flags." 2
    fi
}

# =============================================================================
# Interaction primitives
# =============================================================================

confirm() {
    # confirm "Prompt?" [default=N]
    # Returns 0 on yes, 1 on no. Auto-yes under --yes (non-destructive path).
    local prompt="$1"
    local default="${2:-N}"
    if [[ "$YES" == "1" ]]; then
        return 0
    fi
    local hint="[y/N]"
    [[ "${default^^}" == "Y" ]] && hint="[Y/n]"
    local ans
    printf "  ${SK_CYAN}%s${SK_NC} %s " "$prompt" "$hint" >&2
    IFS= read -r ans
    ans="${ans:-$default}"
    case "${ans,,}" in
        y|yes) return 0 ;;
        *)     return 1 ;;
    esac
}

confirm_destructive() {
    # confirm_destructive "Message"
    # Requires the user to type 'yes' (not 'y'). Under --yes, refuses to
    # auto-confirm unless the caller has already passed an explicit decision
    # flag (which is the caller's responsibility to check with require_flag).
    local msg="$1"
    if [[ "$YES" == "1" ]]; then
        # The caller MUST have called require_flag for every decision input
        # before reaching here. We log the auto-confirm and proceed.
        info "--yes mode: destructive op auto-confirmed: $msg"
        _sk_audit "auto-confirm (via --yes): $msg"
        return 0
    fi
    printf "\n  ${SK_YELLOW}${SK_BOLD}WARNING:${SK_NC} %s\n" "$msg" >&2
    printf "  Type the word ${SK_BOLD}yes${SK_NC} to continue (anything else aborts): " >&2
    local ans
    IFS= read -r ans
    if [[ "$ans" == "yes" ]]; then
        _sk_audit "user confirmed destructive op: $msg"
        return 0
    fi
    info "aborted by user"
    return 1
}

prompt() {
    # prompt "Label" [default] [validator]
    # Reads a value with optional default and validator (shell snippet that
    # receives the value in $1 and returns 0 if valid). Re-prompts on invalid.
    local label="$1"
    local default="${2:-}"
    local validator="${3:-}"
    local hint=""
    [[ -n "$default" ]] && hint=" [$default]"

    if [[ "$YES" == "1" ]]; then
        if [[ -n "$default" ]]; then
            printf '%s\n' "$default"
            return 0
        fi
        die "prompt '$label' needs a value under --yes; pass an explicit flag" 2
    fi

    local ans
    while true; do
        printf "  ${SK_CYAN}%s${SK_NC}%s: " "$label" "$hint" >&2
        IFS= read -r ans
        ans="${ans:-$default}"
        if [[ -z "$ans" ]]; then
            printf "  value required\n" >&2
            continue
        fi
        if [[ -n "$validator" ]]; then
            # shellcheck disable=SC2016
            if ! bash -c "$validator" -- "$ans" >/dev/null 2>&1; then
                printf "  invalid input\n" >&2
                continue
            fi
        fi
        printf '%s\n' "$ans"
        return 0
    done
}

select_one() {
    # select_one "Label" opt1 opt2 opt3 ...
    # Prints a numbered menu and returns the chosen value on stdout.
    local label="$1"; shift
    local opts=("$@")
    if [[ "$YES" == "1" ]]; then
        printf '%s\n' "${opts[0]}"
        return 0
    fi
    printf "  ${SK_CYAN}%s${SK_NC}\n" "$label" >&2
    local i=1
    for o in "${opts[@]}"; do
        printf "    %2d) %s\n" "$i" "$o" >&2
        i=$((i + 1))
    done
    while true; do
        printf "  choice [1-%d]: " "${#opts[@]}" >&2
        local n
        IFS= read -r n
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#opts[@]} )); then
            printf '%s\n' "${opts[$((n - 1))]}"
            return 0
        fi
        printf "  invalid choice\n" >&2
    done
}

# =============================================================================
# Safe file operations
# =============================================================================

safe_tempfile() {
    # safe_tempfile [prefix]
    # Creates a temp file, registers it for cleanup, returns the path on stdout.
    local prefix="${1:-sk}"
    local tmp
    tmp="$(mktemp -t "${prefix}.XXXXXXXX")" || die "mktemp failed" 1
    SK_CLEANUP_PATHS+=("$tmp")
    printf '%s\n' "$tmp"
}

safe_tempdir() {
    # safe_tempdir [prefix]
    local prefix="${1:-sk}"
    local tmp
    tmp="$(mktemp -d -t "${prefix}.XXXXXXXX")" || die "mktemp -d failed" 1
    SK_CLEANUP_PATHS+=("$tmp")
    printf '%s\n' "$tmp"
}

atomic_write() {
    # atomic_write <target>
    # Reads stdin, writes to <target>.new in the same dir, mvs on success.
    # Preserves permissions/owner of the existing target.
    local target="$1"
    local dir
    dir="$(dirname "$target")"
    local tmp="${target}.new"

    # Preserve permissions/owner of existing target if it exists
    local mode="" owner="" group=""
    if [[ -f "$target" ]]; then
        mode="$(stat -c '%a' "$target" 2>/dev/null)" || true
        owner="$(stat -c '%u' "$target" 2>/dev/null)" || true
        group="$(stat -c '%g' "$target" 2>/dev/null)" || true
    fi

    mkdir -p "$dir" || die "cannot create dir $dir" 1
    cat > "$tmp" || die "write failed: $tmp" 1

    if [[ -n "$mode" ]]; then
        chmod "$mode" "$tmp"
        chown "${owner}:${group}" "$tmp"
    else
        chmod 0644 "$tmp"
    fi

    mv -f "$tmp" "$target" || die "atomic mv failed: $tmp -> $target" 1
    _sk_audit "atomic_write $target"
}

backup_file() {
    # backup_file <path>
    # Copies <path> to <path>.bak-YYYYMMDD-HHMMSS. Prints the backup path.
    local path="$1"
    [[ ! -e "$path" ]] && return 0
    local bak="${path}.bak-$(date +%Y%m%d-%H%M%S)"
    cp -a "$path" "$bak" || die "backup_file failed: $path -> $bak" 1
    printf '%s\n' "$bak"
    _sk_audit "backup_file $path -> $bak"
}

# =============================================================================
# Flag parsing
# =============================================================================

parse_standard_flags() {
    # Consumes --help, --version, --yes, --dry-run, --log, --json, --verbose,
    # --quiet from "$@". Leaves unknown args in REMAINING_ARGS.
    REMAINING_ARGS=()
    while (( $# > 0 )); do
        case "$1" in
            -h|--help)
                if declare -f usage >/dev/null; then
                    usage
                else
                    printf 'Usage: %s [OPTIONS]\n' "$SK_SCRIPT_NAME"
                fi
                exit 0
                ;;
            --version)
                # Scripts define SCRIPT_VERSION themselves
                printf '%s %s\n' "$SK_SCRIPT_NAME" "${SCRIPT_VERSION:-0.0.0}"
                exit 0
                ;;
            -y|--yes)
                YES=1
                ;;
            -n|--dry-run)
                DRY_RUN=1
                ;;
            --log)
                _sk_ensure_log_dir
                LOG_FILE="${SK_AUDIT_DIR}/${SK_SCRIPT_NAME}-$(date +%Y%m%d-%H%M%S).log"
                ;;
            --log=*)
                _sk_ensure_log_dir
                LOG_FILE="${1#*=}"
                ;;
            --json)
                JSON=1
                ;;
            -v|--verbose)
                VERBOSE=1
                ;;
            -q|--quiet)
                QUIET=1
                ;;
            --)
                shift
                while (( $# > 0 )); do
                    REMAINING_ARGS+=("$1")
                    shift
                done
                break
                ;;
            *)
                REMAINING_ARGS+=("$1")
                ;;
        esac
        shift
    done

    if [[ "$QUIET" == "1" && "$VERBOSE" == "1" ]]; then
        die "--quiet and --verbose are incompatible" 2
    fi

    _sk_init_colors
}

_sk_ensure_log_dir() {
    if [[ ! -d "$SK_AUDIT_DIR" ]]; then
        if [[ $EUID -eq 0 ]]; then
            mkdir -p "$SK_AUDIT_DIR" && chmod 0750 "$SK_AUDIT_DIR"
        else
            # Fall back to /tmp if not root
            SK_AUDIT_DIR="/tmp/linux-skills-$USER"
            SK_AUDIT_LOG="${SK_AUDIT_DIR}/${SK_SCRIPT_NAME}.log"
            mkdir -p "$SK_AUDIT_DIR"
        fi
    fi
}

run() {
    # run <cmd> [args...]
    # Prints the command (in verbose or dry-run), skips execution under --dry-run.
    if [[ "$VERBOSE" == "1" || "$DRY_RUN" == "1" ]]; then
        printf "  ${SK_CYAN}→${SK_NC} %s\n" "$*"
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        return 0
    fi
    "$@"
}

# =============================================================================
# Audit log (always written for destructive operations)
# =============================================================================

_sk_audit() {
    _sk_ensure_log_dir
    {
        printf '%s [%s] %s\n' "$(date -Iseconds)" "$SK_SCRIPT_NAME" "$*" >> "$SK_AUDIT_LOG"
    } 2>/dev/null || true
}

# =============================================================================
# Cleanup trap — runs on EXIT, INT, TERM, ERR
# =============================================================================

sk_on_exit() {
    # sk_on_exit <function_name>
    # Register a function to run during cleanup. Scripts can add their own.
    SK_CLEANUP_FUNCS+=("$1")
}

_sk_cleanup() {
    local exit_code=$?
    local cmd="${BASH_COMMAND:-}"
    local line="${BASH_LINENO[0]:-}"

    # Remove registered temp paths
    local p
    for p in "${SK_CLEANUP_PATHS[@]}"; do
        [[ -e "$p" ]] && rm -rf "$p" 2>/dev/null || true
    done

    # Call registered cleanup functions
    local fn
    for fn in "${SK_CLEANUP_FUNCS[@]}"; do
        if declare -f "$fn" >/dev/null; then
            "$fn" "$exit_code" 2>/dev/null || true
        fi
    done

    if (( exit_code != 0 )); then
        # On non-zero exit, print a failure banner
        if [[ "${SK_SUPPRESS_FAIL_BANNER:-0}" != "1" ]]; then
            printf "\n${SK_RED}FAILURE:${SK_NC} %s exited %d at line %s\n" \
                   "$SK_SCRIPT_NAME" "$exit_code" "$line" >&2
            [[ -n "$cmd" ]] && printf "  last command: %s\n" "$cmd" >&2
        fi
    fi

    return "$exit_code"
}

trap _sk_cleanup EXIT INT TERM

# =============================================================================
# Summary helper
# =============================================================================

print_summary() {
    # print_summary — prints PASS/WARN/FAIL counts and a percentage score.
    printf "\n${SK_BOLD}=============================================\n"
    printf " SUMMARY\n"
    printf "=============================================${SK_NC}\n"
    printf "  ${SK_GREEN}PASS: %d${SK_NC}\n" "$PASS_COUNT"
    printf "  ${SK_YELLOW}WARN: %d${SK_NC}\n" "$WARN_COUNT"
    printf "  ${SK_RED}FAIL: %d${SK_NC}\n" "$FAIL_COUNT"
    local total=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT))
    if (( total > 0 )); then
        local score=$(( (PASS_COUNT * 100) / total ))
        printf "  ${SK_BOLD}Score: %d%%${SK_NC}\n" "$score"
    fi
    printf "\n"
}
