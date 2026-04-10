#!/usr/bin/env bash
#: Title:       run-test.sh
#: Synopsis:    run-test.sh [--keep] [--suite foundation|tier1|all] [script...]
#: Description: LXD integration test harness for linux-skills sk-* scripts.
#:              Launches a fresh Ubuntu 24.04 container per test, pushes the
#:              repo, runs install-skills-bin core, executes the per-script test
#:              file, and tears down the container on pass. On failure, leaves
#:              the container running and prints the lxc exec command to attach.
#: Author:      Peter Bamuhigire <techguypeter.com>
#: Contact:     +256784464178
#: Version:     0.1.0

set -uo pipefail

SCRIPT_VERSION="0.1.0"

# =============================================================================
# 1. Library + safety
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && cd .. && pwd)"

SK_LIB=""
if [[ -f "$REPO_ROOT/scripts/lib/common.sh" ]]; then
    SK_LIB="$REPO_ROOT/scripts/lib/common.sh"
elif [[ -f "/usr/local/lib/linux-skills/common.sh" ]]; then
    SK_LIB="/usr/local/lib/linux-skills/common.sh"
else
    echo "FATAL: cannot find common.sh" >&2
    exit 5
fi
# shellcheck source=/dev/null
source "$SK_LIB"

# =============================================================================
# 2. Defaults
# =============================================================================

LXD_IMAGE="ubuntu:24.04"
KEEP_ON_FAIL=1
KEEP_ALWAYS=0
SUITE=""
TESTS_TO_RUN=()
CONTAINER_PREFIX="sk-test"
PASS_TESTS=()
FAIL_TESTS=()

# =============================================================================
# 3. Functions
# =============================================================================

usage() {
    cat <<EOF
Usage: run-test.sh [OPTIONS] [script-name...]

LXD integration test harness for linux-skills scripts. Launches a fresh
Ubuntu container for each test, runs install-skills-bin core, then
executes the test file for the script.

OPTIONS:
    --suite <name>      Run a named test suite:
                          foundation - common.sh + install-skills-bin
                          tier1      - every tier-1 (core) script
                          all        - every test file under scripts/tests/
    --keep              Leave containers running after tests (for inspection)
    --image <name>      LXD image to use (default: ubuntu:24.04)

STANDARD FLAGS:
    -h, --help          Show this help and exit
        --version       Print version
    -v, --verbose       Extra diagnostic output

POSITIONAL:
    script-name...      Run tests for specific scripts (e.g. sk-audit sk-lint)

EXIT CODES:
    0  all tests passed
    1  one or more tests failed
    2  usage error
    5  LXD not installed

EXAMPLES:
    # Run the foundation suite (fast)
    sudo ./scripts/tests/run-test.sh --suite foundation

    # Run tier-1 scripts
    sudo ./scripts/tests/run-test.sh --suite tier1

    # Run one specific test
    sudo ./scripts/tests/run-test.sh sk-audit

    # Run everything and keep containers on failure (default)
    sudo ./scripts/tests/run-test.sh --suite all

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# Container lifecycle --------------------------------------------------------

launch_container() {
    local name="$1"
    info "launching $name from $LXD_IMAGE"
    run lxc launch "$LXD_IMAGE" "$name" >/dev/null || return 1

    # Wait until cloud-init / systemd is ready
    local tries=0
    while (( tries < 60 )); do
        if lxc exec "$name" -- systemctl is-system-running --wait 2>/dev/null \
            | grep -qE 'running|degraded'; then
            break
        fi
        sleep 1
        tries=$((tries + 1))
    done
    info "$name ready"
}

push_repo() {
    local name="$1"
    info "pushing repo into $name:/root/linux-skills"
    run lxc exec "$name" -- mkdir -p /root/linux-skills
    # Use tar pipe — faster than lxc file push on many small files
    tar cf - -C "$REPO_ROOT" \
        --exclude='.git' \
        --exclude='node_modules' \
        --exclude='dist' \
        . | lxc exec "$name" -- tar xf - -C /root/linux-skills
}

destroy_container() {
    local name="$1"
    info "destroying $name"
    run lxc delete --force "$name" >/dev/null 2>&1 || true
}

# Test runner ----------------------------------------------------------------

run_one_test() {
    # run_one_test <script-name>
    local script="$1"
    local test_file="$SCRIPT_DIR/${script}.test.sh"

    if [[ ! -f "$test_file" ]]; then
        warn "no test file for $script at $test_file"
        return 0
    fi

    header "TEST: $script"

    local cname
    cname="${CONTAINER_PREFIX}-${script}-$$"

    if ! launch_container "$cname"; then
        FAIL_TESTS+=("$script (launch failed)")
        return 1
    fi

    if ! push_repo "$cname"; then
        FAIL_TESTS+=("$script (push failed)")
        [[ "$KEEP_ON_FAIL" == "1" ]] || destroy_container "$cname"
        return 1
    fi

    info "installing linux-skills engine inside $cname"
    if ! lxc exec "$cname" -- bash -c '
        cd /root/linux-skills
        install -m 0755 scripts/install-skills-bin /usr/local/bin/install-skills-bin
        install -d -m 0755 /usr/local/lib/linux-skills
        install -m 0644 scripts/lib/common.sh /usr/local/lib/linux-skills/common.sh
    '; then
        FAIL_TESTS+=("$script (bootstrap failed)")
        [[ "$KEEP_ON_FAIL" == "1" ]] || destroy_container "$cname"
        return 1
    fi

    # Push the test file into the container and run it
    lxc file push "$test_file" "${cname}/root/${script}.test.sh"
    lxc exec "$cname" -- chmod +x "/root/${script}.test.sh"

    if lxc exec "$cname" -- bash -c "cd /root && SK_TEST_CONTAINER=1 ./${script}.test.sh"; then
        PASS_TESTS+=("$script")
        pass "$script passed"
        if [[ "$KEEP_ALWAYS" != "1" ]]; then
            destroy_container "$cname"
        fi
        return 0
    else
        FAIL_TESTS+=("$script")
        fail "$script failed"
        if [[ "$KEEP_ON_FAIL" == "1" ]]; then
            warn "container kept for inspection: $cname"
            warn "  attach: lxc exec $cname -- bash"
            warn "  destroy: lxc delete --force $cname"
        else
            destroy_container "$cname"
        fi
        return 1
    fi
}

# Suite selection ------------------------------------------------------------

expand_suite() {
    local suite="$1"
    case "$suite" in
        foundation)
            # The foundation tests verify common.sh and install-skills-bin
            echo "common-sh install-skills-bin"
            ;;
        tier1)
            echo "sk-audit sk-update-all-repos sk-new-script sk-lint sk-system-health \
                  sk-disk-hogs sk-open-ports sk-service-health sk-cert-status sk-cron-audit \
                  sk-user-audit sk-ssh-key-audit sk-fail2ban-status sk-journal-errors \
                  sk-backup-verify"
            ;;
        all)
            local f
            for f in "$SCRIPT_DIR"/*.test.sh; do
                [[ -f "$f" ]] || continue
                basename "$f" .test.sh
            done
            ;;
        *)
            die "unknown suite: $suite (use foundation|tier1|all)" 2
            ;;
    esac
}

# =============================================================================
# 4. Flag parsing
# =============================================================================

parse_standard_flags "$@"

while (( ${#REMAINING_ARGS[@]} > 0 )); do
    case "${REMAINING_ARGS[0]}" in
        --suite)
            SUITE="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        --keep)
            KEEP_ALWAYS=1
            REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
            ;;
        --image)
            LXD_IMAGE="${REMAINING_ARGS[1]:-}"
            REMAINING_ARGS=("${REMAINING_ARGS[@]:2}")
            ;;
        *)
            TESTS_TO_RUN+=("${REMAINING_ARGS[0]}")
            REMAINING_ARGS=("${REMAINING_ARGS[@]:1}")
            ;;
    esac
done

# =============================================================================
# 5. Sanity checks
# =============================================================================

require_cmd lxc tar

if ! lxc list >/dev/null 2>&1; then
    die "lxd not initialized — run: sudo lxd init" 5
fi

if [[ -n "$SUITE" ]]; then
    # shellcheck disable=SC2207
    TESTS_TO_RUN+=($(expand_suite "$SUITE"))
fi

if (( ${#TESTS_TO_RUN[@]} == 0 )); then
    die "no tests specified; use --suite <name> or pass script names" 2
fi

# =============================================================================
# 6. Main
# =============================================================================

header "linux-skills integration test harness"
info "image: $LXD_IMAGE"
info "tests: ${TESTS_TO_RUN[*]}"
info "total: ${#TESTS_TO_RUN[@]}"

for script in "${TESTS_TO_RUN[@]}"; do
    run_one_test "$script" || true
done

header "Results"
pass_n="${#PASS_TESTS[@]}"
fail_n="${#FAIL_TESTS[@]}"
printf "  ${SK_GREEN}PASS: %d${SK_NC}\n" "$pass_n"
printf "  ${SK_RED}FAIL: %d${SK_NC}\n" "$fail_n"

if (( fail_n > 0 )); then
    printf "\nFailed tests:\n"
    for t in "${FAIL_TESTS[@]}"; do
        printf "  - %s\n" "$t"
    done
    exit 1
fi

printf "\nAll tests passed.\n"
