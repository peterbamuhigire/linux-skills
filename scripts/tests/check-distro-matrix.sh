#!/usr/bin/env bash
#: Title:       check-distro-matrix.sh
#: Synopsis:    scripts/tests/check-distro-matrix.sh
#: Description: Invariant check for the two-family (Debian/Ubuntu + RHEL) engine.
#:              Asserts that every linux-* specialist skill carries a
#:              "## Distro support" section as its first H2, and that the section
#:              references both families. The linux-sysadmin hub is exempt (it is
#:              a router, not a domain skill). Pure-bash, no container/root needed.
#: Author:      Peter Bamuhigire <techguypeter.com>
#: Contact:     +256784464178
#: Version:     0.1.0

set -uo pipefail

# Repo root = two levels up from this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT" || { echo "FATAL: cannot cd to repo root"; exit 1; }

# Skills exempt from the distro-matrix invariant (routing hub only).
EXEMPT=("linux-sysadmin")

is_exempt() {
    local s="$1" e
    for e in "${EXEMPT[@]}"; do [[ "$s" == "$e" ]] && return 0; done
    return 1
}

PASS=0 FAIL=0
fail() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$*"; }
ok()   { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$*"; }

printf '== Distro-matrix invariant ==\n'

for dir in linux-*/; do
    skill="${dir%/}"
    file="${dir}SKILL.md"
    [[ -f "$file" ]] || continue
    if is_exempt "$skill"; then
        printf '  [SKIP] %s (exempt: routing hub)\n' "$skill"
        continue
    fi

    # 1. Has a "## Distro support" section
    if ! grep -q '^## Distro support' "$file"; then
        fail "$skill: missing '## Distro support' section"
        continue
    fi

    # 2. It is the FIRST H2 in the file
    first_h2="$(grep -n '^## ' "$file" | head -1 | sed 's/:.*//')"
    ds_line="$(grep -n '^## Distro support' "$file" | head -1 | sed 's/:.*//')"
    if [[ "$first_h2" != "$ds_line" ]]; then
        fail "$skill: '## Distro support' is not the first H2 (first H2 at line $first_h2)"
        continue
    fi

    # 3. The section names both families (RHEL/Fedora appears somewhere in the file)
    if ! grep -qiE 'rhel|fedora' "$file"; then
        fail "$skill: no RHEL/Fedora mention"
        continue
    fi

    ok "$skill"
done

printf '\n-- summary --\n  passed: %d\n  failed: %d\n' "$PASS" "$FAIL"
(( FAIL == 0 )) || exit 1
exit 0
