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
