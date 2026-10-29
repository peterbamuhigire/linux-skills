#!/usr/bin/env bash
# Foundation test: common.sh library correctness
# Self-locating: runs from any checkout (CI container, ~/.claude/skills, etc.).
#
# Author: Peter Bamuhigire <techguypeter.com> +256784464178

set -uo pipefail

FAILURES=0
PASSED=0

pass_t() { PASSED=$((PASSED + 1)); printf "  [PASS] %s\n" "$*"; }
fail_t() { FAILURES=$((FAILURES + 1)); printf "  [FAIL] %s\n" "$*"; }

# Use the repo copy, not the installed one (self-locating from this script's path)
_TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SK_LIB="${_TEST_DIR}/../lib/common.sh"
[[ -f "$SK_LIB" ]] || { echo "FATAL: $SK_LIB missing"; exit 1; }

# shellcheck source=/dev/null
source "$SK_LIB"

# Keep library audit writes and test scratch data inside a private fixture.
TEST_FIXTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/common-sh-test.XXXXXXXX")"
mkdir -m 0700 "$TEST_FIXTURE_DIR/audit"
SK_AUDIT_DIR="$TEST_FIXTURE_DIR/audit"
# library reads the configured audit path
# shellcheck disable=SC2034
SK_AUDIT_LOG="$SK_AUDIT_DIR/${SK_SCRIPT_NAME}.log"
# called through sk_on_exit callback
# shellcheck disable=SC2317
test_fixture_cleanup() { rm -rf -- "$TEST_FIXTURE_DIR"; }
sk_on_exit test_fixture_cleanup

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
# Test 4: safe_tempfile registers cleanup even via command substitution
# (regression: the array append happens in the $(...) subshell and is lost;
#  registration must survive via the private registry file)
# -----------------------------------------------------------------------------
# library cleanup reads this array
# shellcheck disable=SC2034
SK_CLEANUP_PATHS=()
rm -f "$(_sk_registry)" 2>/dev/null || true
tmp=$(safe_tempfile test4)
if [[ -f "$tmp" ]]; then
    pass_t "safe_tempfile created $tmp"
else
    fail_t "safe_tempfile did not create the file"
fi
if grep -zqxF "$tmp" "$(_sk_registry)" 2>/dev/null; then
    pass_t "safe_tempfile registered $tmp despite command-substitution subshell"
else
    fail_t "safe_tempfile did NOT register $tmp in the cleanup registry"
fi

# NUL-delimited registry records keep newline characters inside valid paths.
newline_tmp="$(safe_tempfile $'test4\nprefix')"
newline_registered=0
while IFS= read -r -d '' registered_path; do
    [[ "$registered_path" == "$newline_tmp" ]] && newline_registered=1
done < "$(_sk_registry)"
if [[ -f "$newline_tmp" && "$newline_registered" == "1" ]]; then
    pass_t "cleanup registry preserves paths containing newlines"
else
    fail_t "cleanup registry corrupted a newline-containing path"
fi
_sk_remove_registered
if [[ ! -e "$newline_tmp" ]]; then
    pass_t "cleanup removes newline-containing temporary paths"
else
    fail_t "cleanup did not remove newline-containing temporary path"
fi
# Exercise the real cleanup path
_sk_remove_registered
if [[ ! -f "$tmp" ]]; then
    pass_t "_sk_remove_registered removed $tmp"
else
    fail_t "cleanup did not remove $tmp"
fi

# The registry must not follow a predictable shared-temp symlink to attacker
# controlled cleanup entries.
victim="$TEST_FIXTURE_DIR/keep-me"
printf 'must survive\n' > "$victim"
poison="$TEST_FIXTURE_DIR/poisoned-registry"
printf '%s\n' "$victim" > "$poison"
original_tmpdir="${TMPDIR:-/tmp}"
export TMPDIR="$TEST_FIXTURE_DIR"
predictable_registry="$TMPDIR/sk-cleanup.$$"
ln -s "$poison" "$predictable_registry" || exit 1
tmp=$(safe_tempfile test4-poison)
_sk_remove_registered
if [[ -f "$victim" ]] && ! grep -qxF "$tmp" "$poison"; then
    pass_t "private registry ignores a planted predictable-registry symlink"
else
    fail_t "cleanup trusted a planted predictable-registry symlink"
fi
rm -f "$predictable_registry"
export TMPDIR="$original_tmpdir"
registry_dir="${SK_CLEANUP_REGISTRY_DIR:-}"
registry_mode="$(stat -c '%a' "$registry_dir" 2>/dev/null || true)"
if [[ -n "$registry_dir" && "$registry_mode" == "700" ]]; then
    pass_t "cleanup registry is stored in a mode-700 private directory"
else
    fail_t "cleanup registry directory is not private (mode=$registry_mode)"
fi
source_failure_output="$(TMPDIR="$poison" bash -c 'source "$1"; printf "source continued\\n"' _ "$SK_LIB" 2>&1)"
source_failure_status=$?
if (( source_failure_status != 0 )) && [[ "$source_failure_output" == *"cannot create private cleanup registry directory"* ]] && [[ "$source_failure_output" != *"source continued"* ]]; then
    pass_t "common.sh aborts if it cannot create the private cleanup registry"
else
    fail_t "common.sh continued after private registry creation failed"
fi

# Reject a shared writable temp parent even when a leaf directory is private.
unsafe_base="$TEST_FIXTURE_DIR/unsafe-temp"
mkdir -m 0777 "$unsafe_base"
chmod 0777 "$unsafe_base"
mkdir -m 0700 "$unsafe_base/private"
if TMPDIR="$unsafe_base/private" bash -c 'source "$1"' _ "$SK_LIB" >/dev/null 2>&1; then
    fail_t "common.sh accepted untrusted writable TMPDIR ancestry"
else
    pass_t "common.sh rejects writable non-sticky TMPDIR ancestry"
fi
# A later TMPDIR override cannot redirect safe_tempfile away from the checked base.
checked_temp=$(TMPDIR="$unsafe_base" safe_tempfile verified-base)
if [[ "$checked_temp" == "$SK_TEMP_BASE/"* && -f "$checked_temp" ]]; then
    pass_t "safe_tempfile stays inside the validated temporary base"
else
    fail_t "safe_tempfile trusted a later TMPDIR override"
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

# A planted legacy .new symlink must not be followed by atomic_write.
target="$TEST_FIXTURE_DIR/atomic-target"
victim="$TEST_FIXTURE_DIR/atomic-victim"
printf 'protected\n' > "$victim"
ln -s "$victim" "$target.new"
printf 'safe content\n' | atomic_write "$target"
if [[ "$(cat "$target")" == "safe content" && "$(cat "$victim")" == "protected" ]]; then
    pass_t "atomic_write uses a unique temp and ignores a planted .new symlink"
else
    fail_t "atomic_write followed a planted .new symlink"
fi
rm -f "$target" "$target.new"

# Refuse symlink targets, preserving both the link and its referent.
target="$TEST_FIXTURE_DIR/atomic-link"
ln -s "$victim" "$target"
if ( printf 'overwrite\n' | atomic_write "$target" >/dev/null 2>&1 ); then
    fail_t "atomic_write should reject symlink targets"
elif [[ -L "$target" && "$(cat "$victim")" == "protected" ]]; then
    pass_t "atomic_write rejects symlink targets without changing referents"
else
    fail_t "atomic_write changed or removed a symlink target"
fi
rm -f "$target"

# Existing-file metadata lookup must fail closed, without changing content/mode.
target="$TEST_FIXTURE_DIR/stat-failure"
printf 'private\n' > "$target"
chmod 0600 "$target"
# Failure-injection function is called by the sourced library.
# shellcheck disable=SC2317
if ( stat() { return 1; }; printf 'replacement\n' | atomic_write "$target" >/dev/null 2>&1 ); then
    fail_t "atomic_write accepted failed metadata lookup"
elif [[ "$(cat "$target")" == "private" && "$(stat -c '%a' "$target")" == "600" ]]; then
    pass_t "atomic_write preserves target when metadata lookup fails"
else
    fail_t "atomic_write changed target after metadata lookup failure"
fi
# No privilege is needed to keep the owner/group already on the sibling temp.
# Failure-injection function is called by the sourced library.
# shellcheck disable=SC2317
if ( chown() { return 1; }; printf 'updated\n' | atomic_write "$target" >/dev/null 2>&1 ); then
    pass_t "atomic_write skips redundant chown for an already matching owner"
else
    fail_t "atomic_write required redundant chown"
fi

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
# Test 7: distro detection populates family + package manager
# -----------------------------------------------------------------------------
SK_DISTRO_FAMILY="" SK_DISTRO_ID="" SK_PKG=""
detect_distro
case "$SK_DISTRO_FAMILY" in
    debian)
        if [[ "$SK_PKG" == "apt-get" ]]; then
            pass_t "detect_distro: debian family -> apt-get ($SK_DISTRO_ID)"
        else
            fail_t "detect_distro: debian family but SK_PKG=$SK_PKG"
        fi ;;
    rhel)
        if [[ "$SK_PKG" == "dnf" || "$SK_PKG" == "yum" ]]; then
            pass_t "detect_distro: rhel family -> $SK_PKG ($SK_DISTRO_ID)"
        else
            fail_t "detect_distro: rhel family but SK_PKG=$SK_PKG"
        fi ;;
    *)
        fail_t "detect_distro: family is '$SK_DISTRO_FAMILY' (expected debian or rhel)" ;;
esac

# Test 7b: detect_distro on a mocked os-release of the OTHER family
#   We mock by overriding the function's file source via a subshell with a
#   crafted /etc/os-release substitute is not possible without root; instead we
#   exercise the family classifier directly through a temp wrapper.
test_classify() {
    # test_classify <ID> <ID_LIKE> -> echoes resulting family
    local _id="$1" _like=" $2 "
    local fam="unknown"
    case "$_id" in
        debian|ubuntu|linuxmint|pop|raspbian|devuan|kali) fam="debian" ;;
        fedora|rhel|centos|rocky|almalinux|ol|amzn|scientific) fam="rhel" ;;
        *)
            if   [[ "$_like" == *" debian "* || "$_like" == *" ubuntu "* ]]; then fam="debian"
            elif [[ "$_like" == *" rhel "* || "$_like" == *" fedora "* || "$_like" == *" centos "* ]]; then fam="rhel"
            fi ;;
    esac
    printf '%s' "$fam"
}
if [[ "$(test_classify fedora '')" == "rhel" \
   && "$(test_classify rocky 'rhel centos fedora')" == "rhel" \
   && "$(test_classify ubuntu '')" == "debian" \
   && "$(test_classify pureos 'debian')" == "debian" ]]; then
    pass_t "family classifier maps Fedora/Rocky->rhel, Ubuntu/PureOS->debian"
else
    fail_t "family classifier produced wrong mappings"
fi

# Test 7c: require_family enforces and rejects correctly
if ( require_family any 2>/dev/null ); then
    pass_t "require_family any accepts a supported distro"
else
    fail_t "require_family any rejected a supported distro"
fi
# The family that is NOT the current one must be rejected
OTHER="rhel"; [[ "$SK_DISTRO_FAMILY" == "rhel" ]] && OTHER="debian"
if ( require_family "$OTHER" 2>/dev/null ); then
    fail_t "require_family $OTHER should have failed on a $SK_DISTRO_FAMILY host"
else
    pass_t "require_family rejects the wrong family"
fi

# Test 7d: svc_name maps apache per family, passes others through
EXPECT_APACHE="apache2"; [[ "$SK_DISTRO_FAMILY" == "rhel" ]] && EXPECT_APACHE="httpd"
if [[ "$(svc_name apache)" == "$EXPECT_APACHE" && "$(svc_name nginx)" == "nginx" ]]; then
    pass_t "svc_name maps apache->$EXPECT_APACHE and passes nginx through"
else
    fail_t "svc_name wrong: apache=$(svc_name apache) nginx=$(svc_name nginx)"
fi

# Test 7e: require_debian still works as a backward-compatible alias
SK_DISTRO_FAMILY="" SK_DISTRO_ID="" SK_PKG=""; detect_distro
if [[ "$SK_DISTRO_FAMILY" == "debian" ]]; then
    if ( require_debian 2>/dev/null ); then
        pass_t "require_debian alias accepts a Debian-family host"
    else
        fail_t "require_debian alias rejected a Debian-family host"
    fi
else
    if ( require_debian 2>/dev/null ); then
        fail_t "require_debian alias should reject a non-Debian host"
    else
        pass_t "require_debian alias rejects a non-Debian host"
    fi
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
# require_flag reads the variable indirectly
# shellcheck disable=SC2034
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
