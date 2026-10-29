#!/usr/bin/env bash
#: Title:       check-distro-matrix.sh
#: Synopsis:    scripts/tests/check-distro-matrix.sh
#: Description: Verify that each Linux specialist has a two-family matrix as
#:              its first H2; network-appliance skills are outside this gate.
#: Author:      Peter Bamuhigire <techguypeter.com>
#: Contact:     +256784464178
#: Version:     0.2.0

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SKILLS_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
if [[ ! -d "$REPO_ROOT" ]]; then
    printf 'FATAL: skills root is not a directory: %s\n' "$REPO_ROOT" >&2
    exit 2
fi

# The routing hub is exempt. Vendor appliance skills are outside the search
# globs because their names do not begin with linux-.
EXEMPT=(linux-sysadmin)
is_exempt() {
    local skill="$1" item
    for item in "${EXEMPT[@]}"; do
        [[ "$skill" == "$item" ]] && return 0
    done
    return 1
}

PASS=0
FAIL=0
fail() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$*"; }
ok() { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$*"; }

section_for() {
    local file="$1"
    awk '
        /^##[[:space:]]/ {
            if (started) exit
            if ($0 ~ /^##[[:space:]]+Distro support[[:space:]]*$/) started=1
        }
        started { print }
    ' "$file"
}

has_family_matrix() {
    local section="$1"
    local debian=0 rhel=0 table_rows=0 has_separator=0 line
    while IFS= read -r line; do
        [[ "$line" == *'|'* ]] || continue
        table_rows=$((table_rows + 1))
        [[ "$line" =~ [Dd]ebian|[Uu]buntu ]] && debian=1
        [[ "$line" =~ [Rr][Hh][Ee][Ll]|[Ff]edora ]] && rhel=1
        [[ "$line" =~ \|[[:space:]]*:?-{3,} ]] && has_separator=1
    done <<< "$section"
    (( debian == 1 && rhel == 1 && table_rows >= 3 && has_separator == 1 ))
}

has_bash_primitive_matrix() {
    local section="$1" primitive line has_separator=0
    [[ "$section" == *"common.sh"* && "$section" == *"Use this primitive"* ]] || return 1
    while IFS= read -r line; do
        [[ "$line" =~ \|[[:space:]]*:?-{3,} ]] && has_separator=1
    done <<< "$section"
    (( has_separator == 1 )) || return 1
    for primitive in detect_distro pkg_install pkg_is_installed svc_name firewall_allow web_conf_dir web_reload require_family; do
        [[ "$section" == *"$primitive"* ]] || return 1
    done
}

printf '== Distro-matrix invariant ==\n'
PASS=0
FAIL=0
shopt -s nullglob
files=("$REPO_ROOT"/linux-*/SKILL.md "$REPO_ROOT"/[0-9]*-*/linux-*/SKILL.md)
shopt -u nullglob

if (( ${#files[@]} == 0 )); then
    fail "no Linux skill contracts found under $REPO_ROOT"
else
    for file in "${files[@]}"; do
        skill="$(basename "$(dirname "$file")")"
        if is_exempt "$skill"; then
            printf '  [SKIP] %s (exempt: routing hub)\n' "$skill"
            continue
        fi

        first_h2="$(grep -m1 -E '^##[[:space:]]+' "$file" || true)"
        if [[ "$first_h2" != '## Distro support' ]]; then
            fail "$skill: Distro support must be the exact first H2 (found: ${first_h2:-none})"
            continue
        fi

        section="$(section_for "$file")"
        if [[ "$skill" == linux-bash-scripting ]]; then
            if has_bash_primitive_matrix "$section" && [[ "$section" == *Debian* && "$section" == *RHEL* ]]; then
                ok "$skill: two-family common.sh primitive map"
            else
                fail "$skill: Distro support must retain both families and the common.sh primitive map"
            fi
        elif has_family_matrix "$section"; then
            ok "$skill: family comparison table in Distro support"
        else
            fail "$skill: first Distro support section needs table rows naming Debian/Ubuntu and RHEL/Fedora"
        fi
    done
fi

printf '\n-- summary --\n  passed: %d\n  failed: %d\n' "$PASS" "$FAIL"
(( FAIL == 0 )) || exit 1
exit 0
