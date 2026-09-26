#!/usr/bin/env bash
# Foundation test: install-skills-bin installer correctness
# Self-locating, but DESTRUCTIVE (installs/uninstalls under /usr/local) — run
# only in a throwaway container/VM, never on a workstation you care about.
#
# Author: Peter Bamuhigire <techguypeter.com> +256784464178

set -uo pipefail

FAILURES=0
PASSED=0

pass_t() { PASSED=$((PASSED + 1)); printf "  [PASS] %s\n" "$*"; }
fail_t() { FAILURES=$((FAILURES + 1)); printf "  [FAIL] %s\n" "$*"; }

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || { echo "FATAL: cannot locate repo root"; exit 1; }

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
# Test 3a: --list distinguishes root, skill-local, and missing sources
# -----------------------------------------------------------------------------
list_output=$(scripts/install-skills-bin --list 2>&1)
if printf '%s\n' "$list_output" | awk '$1 == "sk-service-priority" && $2 == "linux-service-management" && $4 == "available" { found=1 } END { exit !found }'; then
    pass_t "--list resolves engine-root script sources"
else
    fail_t "--list did not resolve an engine-root script source"
fi

if printf '%s\n' "$list_output" | awk '$1 == "sk-module-info" && $2 == "linux-kernel-modules" && $4 == "available" { found=1 } END { exit !found }'; then
    pass_t "--list resolves skill-local script sources"
else
    fail_t "--list did not resolve a skill-local script source"
fi

if printf '%s\n' "$list_output" | awk '$1 == "sk-file-integrity-init" && $2 == "linux-file-integrity" && $4 == "missing" { found=1 } END { exit !found }'; then
    pass_t "--list identifies missing manifest sources"
else
    fail_t "--list did not identify a missing manifest source"
fi

# -----------------------------------------------------------------------------
# Test 3b: dry-run summary does not count missing sources as installed
# -----------------------------------------------------------------------------
missing_output=$(scripts/install-skills-bin linux-file-integrity --dry-run 2>&1)
if printf '%s\n' "$missing_output" | grep -q '0/2 scripts installed; 2 missing sources; 0 failed'; then
    pass_t "missing manifest sources are excluded from installed totals"
else
    fail_t "missing source summary was inaccurate: $missing_output"
fi

# -----------------------------------------------------------------------------
# Test 3c: dry-run uses the skill-local source path when the engine path is absent
# -----------------------------------------------------------------------------
local_output=$(scripts/install-skills-bin linux-kernel-modules --dry-run 2>&1)
if printf '%s\n' "$local_output" | grep -q 'linux-kernel-modules/scripts/sk-module-info.sh'; then
    pass_t "dry-run resolves skill-local script source"
else
    fail_t "dry-run did not resolve skill-local script source: $local_output"
fi

# -----------------------------------------------------------------------------
# Test 4: --dry-run core doesn't actually install anything
# -----------------------------------------------------------------------------
# Remove any pre-installed sk-* just in case
rm -f /usr/local/bin/sk-* 2>/dev/null || true

dry_run_output=$(scripts/install-skills-bin core --dry-run 2>&1)
dry_run_result=$?
if printf '%s\n' "$dry_run_output" | grep -q 'core install complete:'; then
    pass_t "core --dry-run reaches its truthful source summary (exit $dry_run_result)"
else
    fail_t "core --dry-run did not reach its source summary: $dry_run_output"
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
core_output=$(scripts/install-skills-bin core 2>&1)
core_result=$?
if printf '%s\n' "$core_output" | grep -Eq 'core install complete: .*; [1-9][0-9]* missing sources; [0-9]+ failed' && (( core_result != 0 )); then
    pass_t "core install reports unavailable required sources and returns nonzero"
elif printf '%s\n' "$core_output" | grep -q 'core install complete: .*; 0 missing sources; 0 failed' && (( core_result == 0 )); then
    pass_t "core install succeeds when all required sources are available"
else
    fail_t "core install status disagreed with its source summary: $core_output"
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
