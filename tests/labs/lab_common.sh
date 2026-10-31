#!/usr/bin/env bash
#: Title: Shared helpers for the in-container distro lab drivers
#: Author: Peter Bamuhigire <techguypeter.com>
#: Contact: +256784464178
# Sourced by the drivers in tests/labs/. Each driver prints PASS, FAIL or INFO lines and ends with
# "### RESULT: ALL-PASS" or "### RESULT: HAS-FAILURES"; tests/test_distro_labs.py reads that.

if [[ ! -f /run/.containerenv && ! -f /.dockerenv ]] || [[ "${SK_LAB_DISPOSABLE:-}" != 1 ]]; then
    printf 'Refusing: these drivers change the system they run on; they need a disposable container and SK_LAB_DISPOSABLE=1\n' >&2
    exit 3
fi

LAB_RESULT=0
lab_ok()    { printf 'PASS  %s\n' "$*"; }
lab_bad()   { printf 'FAIL  %s\n' "$*"; LAB_RESULT=1; }
lab_info()  { printf 'INFO  %s\n' "$*"; }
# check LABEL cmd...   passes when the command succeeds
check()     { local label=$1; shift; if "$@"; then lab_ok "$label"; else lab_bad "$label"; fi; }
# nocheck LABEL cmd... passes when the command fails
nocheck()   { local label=$1; shift; if "$@"; then lab_bad "$label"; else lab_ok "$label"; fi; }
lab_finish() {
    printf '### RESULT: %s\n' "$([[ $LAB_RESULT -eq 0 ]] && echo ALL-PASS || echo HAS-FAILURES)"
    exit "$LAB_RESULT"
}
