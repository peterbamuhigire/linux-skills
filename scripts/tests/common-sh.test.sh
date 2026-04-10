#!/usr/bin/env bash
# Foundation test: common.sh library correctness
# Runs inside a fresh LXD container with the repo at /root/linux-skills.
#
# Author: Peter Bamuhigire <techguypeter.com> +256784464178

set -uo pipefail

FAILURES=0
PASSED=0

pass_t() { PASSED=$((PASSED + 1)); printf "  [PASS] %s\n" "$*"; }
fail_t() { FAILURES=$((FAILURES + 1)); printf "  [FAIL] %s\n" "$*"; }

# Use the repo copy, not the installed one
SK_LIB=/root/linux-skills/scripts/lib/common.sh
[[ -f "$SK_LIB" ]] || { echo "FATAL: $SK_LIB missing"; exit 1; }

# shellcheck source=/dev/null
source "$SK_LIB"

# -----------------------------------------------------------------------------
# Test 1: output primitives increment counters correctly
# -----------------------------------------------------------------------------
PASS_COUNT=0 WARN_COUNT=0 FAIL_COUNT=0
pass "test1" >/dev/null
pass "test1b" >/dev/null
warn "test1c" >/dev/null
fail "test1d" >/dev/null
if (( PASS_COUNT == 2 && WARN_COUNT == 1 && FAIL_COUNT == 1 )); then
    pass_t "pass/warn/fail increment counters"
else
    fail_t "counters wrong: PASS=$PASS_COUNT WARN=$WARN_COUNT FAIL=$FAIL_COUNT"
fi

# -----------------------------------------------------------------------------
# Test 2: parse_standard_flags consumes flags correctly
# -----------------------------------------------------------------------------
DRY_RUN=0 YES=0 VERBOSE=0
parse_standard_flags --yes --dry-run -v somearg --extra
if (( YES == 1 && DRY_RUN == 1 && VERBOSE == 1 )); then
    pass_t "parse_standard_flags sets globals"
else
    fail_t "parse_standard_flags globals wrong"
fi
if [[ "${REMAINING_ARGS[*]}" == "somearg --extra" ]]; then
    pass_t "parse_standard_flags preserves unknown args"
else
    fail_t "REMAINING_ARGS wrong: ${REMAINING_ARGS[*]}"
fi

# -----------------------------------------------------------------------------
# Test 3: --quiet + --verbose incompatibility
# -----------------------------------------------------------------------------
# Run in a subshell so the die() doesn't kill the test
if ( parse_standard_flags --quiet --verbose 2>/dev/null ); then
    fail_t "--quiet + --verbose should fail"
else
    pass_t "--quiet + --verbose rejected"
fi

# -----------------------------------------------------------------------------
# Test 4: safe_tempfile + cleanup trap removes the file
# -----------------------------------------------------------------------------
SK_CLEANUP_PATHS=()
tmp=$(safe_tempfile test4)
if [[ -f "$tmp" ]]; then
    pass_t "safe_tempfile created $tmp"
else
    fail_t "safe_tempfile did not create the file"
fi
# Simulate cleanup
_sk_cleanup_test() {
    local p
    for p in "${SK_CLEANUP_PATHS[@]}"; do
        [[ -e "$p" ]] && rm -rf "$p"
    done
}
_sk_cleanup_test
if [[ ! -f "$tmp" ]]; then
    pass_t "safe_tempfile cleanup removed $tmp"
else
    fail_t "cleanup did not remove $tmp"
fi

# -----------------------------------------------------------------------------
# Test 5: atomic_write preserves content and mode
# -----------------------------------------------------------------------------
target=$(mktemp)
echo "original content" > "$target"
chmod 0600 "$target"
echo "new content" | atomic_write "$target"
if [[ "$(cat "$target")" == "new content" ]]; then
    pass_t "atomic_write replaced content"
else
    fail_t "atomic_write: content not replaced"
fi
mode=$(stat -c '%a' "$target")
if [[ "$mode" == "600" ]]; then
    pass_t "atomic_write preserved mode 600"
else
    fail_t "atomic_write mode wrong: $mode"
fi
rm -f "$target"

# -----------------------------------------------------------------------------
# Test 6: backup_file creates the backup
# -----------------------------------------------------------------------------
target=$(mktemp)
echo "important" > "$target"
bak=$(backup_file "$target")
if [[ -f "$bak" ]] && [[ "$(cat "$bak")" == "important" ]]; then
    pass_t "backup_file created a backup at $bak"
else
    fail_t "backup_file failed"
fi
rm -f "$target" "$bak"

# -----------------------------------------------------------------------------
# Test 7: require_debian passes on Ubuntu
# -----------------------------------------------------------------------------
if ( require_debian 2>/dev/null ); then
    pass_t "require_debian accepts Ubuntu"
else
    fail_t "require_debian rejected Ubuntu"
fi

# -----------------------------------------------------------------------------
# Test 8: require_cmd detects missing command
# -----------------------------------------------------------------------------
if ( require_cmd this-command-does-not-exist-abc 2>/dev/null ); then
    fail_t "require_cmd should have failed on missing command"
else
    pass_t "require_cmd detects missing command"
fi

# -----------------------------------------------------------------------------
# Test 9: require_flag under --yes with empty var aborts
# -----------------------------------------------------------------------------
YES=1
DOMAIN=""
if ( require_flag DOMAIN 2>/dev/null ); then
    fail_t "require_flag should have failed with empty DOMAIN under --yes"
else
    pass_t "require_flag enforces decision flags under --yes"
fi
YES=0

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
printf "\n--- common.sh test summary ---\n"
printf "  passed: %d\n" "$PASSED"
printf "  failed: %d\n" "$FAILURES"

if (( FAILURES > 0 )); then
    exit 1
fi
exit 0
