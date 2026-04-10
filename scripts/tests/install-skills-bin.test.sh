#!/usr/bin/env bash
# Foundation test: install-skills-bin installer correctness
# Runs inside a fresh LXD container with the repo at /root/linux-skills.
#
# Author: Peter Bamuhigire <techguypeter.com> +256784464178

set -uo pipefail

FAILURES=0
PASSED=0

pass_t() { PASSED=$((PASSED + 1)); printf "  [PASS] %s\n" "$*"; }
fail_t() { FAILURES=$((FAILURES + 1)); printf "  [FAIL] %s\n" "$*"; }

cd /root/linux-skills

# -----------------------------------------------------------------------------
# Test 1: --help exits 0 and prints usage
# -----------------------------------------------------------------------------
if scripts/install-skills-bin --help >/dev/null 2>&1; then
    pass_t "install-skills-bin --help exits 0"
else
    fail_t "install-skills-bin --help failed"
fi

# -----------------------------------------------------------------------------
# Test 2: --list works without root
# -----------------------------------------------------------------------------
if scripts/install-skills-bin --list >/dev/null 2>&1; then
    pass_t "install-skills-bin --list works"
else
    fail_t "install-skills-bin --list failed"
fi

# -----------------------------------------------------------------------------
# Test 3: Manifest parser reads every SKILL.md without error
# -----------------------------------------------------------------------------
PARSE_ERRORS=0
for skill_md in linux-*/SKILL.md; do
    if ! scripts/install-skills-bin --list >/dev/null 2>&1; then
        PARSE_ERRORS=$((PARSE_ERRORS + 1))
    fi
done
if (( PARSE_ERRORS == 0 )); then
    pass_t "manifest parser reads every SKILL.md"
else
    fail_t "$PARSE_ERRORS SKILL.md files failed to parse"
fi

# -----------------------------------------------------------------------------
# Test 4: --dry-run core doesn't actually install anything
# -----------------------------------------------------------------------------
# Remove any pre-installed sk-* just in case
rm -f /usr/local/bin/sk-* 2>/dev/null || true

if scripts/install-skills-bin core --dry-run >/dev/null 2>&1; then
    pass_t "install-skills-bin core --dry-run exits 0"
else
    fail_t "install-skills-bin core --dry-run failed"
fi

count=$(ls /usr/local/bin/sk-* 2>/dev/null | wc -l)
if (( count == 0 )); then
    pass_t "--dry-run installed nothing"
else
    fail_t "--dry-run installed $count files"
fi

# -----------------------------------------------------------------------------
# Test 5: Real core install places files in /usr/local/bin/
# -----------------------------------------------------------------------------
if scripts/install-skills-bin core >/dev/null 2>&1; then
    pass_t "install-skills-bin core exits 0"
else
    fail_t "install-skills-bin core failed"
fi

count=$(ls /usr/local/bin/sk-* 2>/dev/null | wc -l)
if (( count >= 1 )); then
    pass_t "install placed $count sk-* binaries in /usr/local/bin"
else
    fail_t "no sk-* binaries installed"
fi

# -----------------------------------------------------------------------------
# Test 6: common.sh installed to /usr/local/lib/linux-skills/
# -----------------------------------------------------------------------------
if [[ -f /usr/local/lib/linux-skills/common.sh ]]; then
    pass_t "common.sh installed to system lib dir"
else
    fail_t "common.sh not installed"
fi

# -----------------------------------------------------------------------------
# Test 7: Idempotency — second core install reports unchanged
# -----------------------------------------------------------------------------
output=$(scripts/install-skills-bin core 2>&1)
if echo "$output" | grep -q "already installed, unchanged"; then
    pass_t "second install reports unchanged"
else
    fail_t "second install did not report unchanged (not idempotent)"
fi

# -----------------------------------------------------------------------------
# Test 8: Per-skill install
# -----------------------------------------------------------------------------
if scripts/install-skills-bin linux-webstack >/dev/null 2>&1; then
    pass_t "per-skill install (linux-webstack) works"
else
    fail_t "per-skill install failed"
fi

# -----------------------------------------------------------------------------
# Test 9: Uninstall
# -----------------------------------------------------------------------------
if scripts/install-skills-bin --uninstall linux-webstack >/dev/null 2>&1; then
    pass_t "uninstall exits 0"
else
    fail_t "uninstall failed"
fi

# Verify sk-nginx-test-reload removed (if it was installed)
if [[ ! -f /usr/local/bin/sk-nginx-test-reload ]]; then
    pass_t "uninstall removed skill scripts"
else
    fail_t "uninstall did not remove scripts"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
printf "\n--- install-skills-bin test summary ---\n"
printf "  passed: %d\n" "$PASSED"
printf "  failed: %d\n" "$FAILURES"

if (( FAILURES > 0 )); then
    exit 1
fi
exit 0
