#!/usr/bin/env bash
#: Title: Debian unattended-upgrades lab: do the documented origins match the security archive?
#: Synopsis: SK_LAB_DISPOSABLE=1 unattended_upgrades_lab.sh <blocks-dir>
#: Description: Runs the documented Debian configuration block and the documented dry-run command, then
#:              checks the effective origins against the security archive's own Release fields and against
#:              apt's list of pending security upgrades. <blocks-dir> holds debian.sh (the documented
#:              configuration block) and verify.sh (the documented dry-run command).
#: Author: Peter Bamuhigire <techguypeter.com>
#: Contact: +256784464178
set -u
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/labs/lab_common.sh
source "$LAB_DIR/lab_common.sh"
BLOCKS=${1:?usage: unattended_upgrades_lab.sh <blocks-dir>}

. /etc/os-release
lab_info "$PRETTY_NAME"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1

# Packages apt would upgrade from a security archive right now (empty when the image is fully patched).
pending=$(apt-get -s dist-upgrade | awk '/^Inst/ && /-security/ {print $2}' | sort)
lab_info "pending security upgrades before the procedure: ${pending:-none}"

echo; echo "=== the archive's own Release fields"
release=$(ls /var/lib/apt/lists/*-security*_InRelease 2>/dev/null | head -1)
check "a security archive Release file is present" test -n "$release"
origin=$(sed -n 's/^Origin: //p' "$release" | head -1)
label=$(sed -n 's/^Label: //p' "$release" | head -1)
codename=$(sed -n 's/^Codename: //p' "$release" | head -1)
suite=$(sed -n 's/^Suite: //p' "$release" | head -1)
lab_info "security archive: Origin=$origin Label=$label Suite=$suite Codename=$codename"
check "the Suite is not the codename (the reason the Ubuntu pattern cannot match on Debian)" test "$suite" != "$codename"

echo; echo "=== documented configuration block, verbatim"
bash "$BLOCKS/debian.sh"; rc=$?
check "configuration block exits 0" test $rc -eq 0

echo; echo "=== documented verify command, verbatim"
bash "$BLOCKS/verify.sh" > /root/uu-verify.out 2>&1
tail -n 6 /root/uu-verify.out
check "the dry run names origins ('Allowed origins are')" grep -q 'Allowed origins are' /root/uu-verify.out
check "the origins include the security archive's Label ($label)" grep -q "label=$label" /root/uu-verify.out
check "the origins include the security archive's Codename ($codename)" grep -q "codename=$codename" /root/uu-verify.out
nocheck "the dry run does not report 'No packages found' while security upgrades are pending" \
    bash -c "[[ -n '$pending' ]] && grep -q 'No packages found' /root/uu-verify.out"
for pkg in $pending; do
    check "pending security upgrade $pkg is listed to be upgraded" bash -c "grep 'Packages that will be upgraded' /root/uu-verify.out | grep -qw '$pkg'"
done
[[ -n "$pending" ]] || lab_info "no security upgrade was pending: the per-package check was not exercised, only the origin match"

lab_finish
