#!/usr/bin/env bash
#: Title:       sk-kernel-rollback
#: Synopsis:    sk-kernel-rollback [--list | --to <version>] [standard flags]
#: Description: List installed kernels and set a chosen prior kernel as the GRUB2
#:              default, on Debian/Ubuntu or the RHEL family (Fedora, RHEL,
#:              CentOS Stream, Rocky, Alma, Oracle). After a kernel panic you boot
#:              the previous kernel from the GRUB menu (one-time), then run this to
#:              make it the persistent default so the next reboot is safe. With
#:              --list it is READ-ONLY: it prints installed kernels and marks the
#:              running one and the current default. With no flag it is
#:              interactive: pick a kernel and confirm; it sets the default via
#:              grubby (RHEL) or grub-set-default + update-grub (Debian). It never
#:              removes a kernel — that is a deliberate manual step after a good
#:              boot. See references/grub2-and-kernel-rollback.md.
#: Author:      Peter Bamuhigire <techguypeter.com>
#: Contact:     +256784464178
#: Version:     0.1.0

# =============================================================================
# 1. Library + safety
# =============================================================================
set -uo pipefail

SK_LIB="/usr/local/lib/linux-skills/common.sh"
if [[ ! -f "$SK_LIB" ]]; then
    _SD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SK_LIB="${_SD}/lib/common.sh"
fi
# shellcheck source=/dev/null
source "$SK_LIB" || { echo "FATAL: cannot source common.sh" >&2; exit 5; }

# =============================================================================
# 2. Defaults
# =============================================================================
SCRIPT_VERSION="0.1.0"

LIST_ONLY=0
TARGET_VERSION=""

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-kernel-rollback [OPTIONS]

List installed kernels and set a chosen prior kernel as the GRUB2 default, on
Debian/Ubuntu or the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma,
Oracle).

Use after a kernel panic: boot the previous kernel from the GRUB menu (one
time), confirm with `uname -r`, then run this to make that kernel the persistent
default so the next unattended reboot is safe.

With --list this is READ-ONLY. With no flag it is interactive (pick + confirm).
It NEVER removes a kernel — purge/blacklist the bad kernel manually only after a
known-good kernel has booted (see the reference).

OPTIONS:
        --list              Read-only: list installed kernels; mark running + default.
        --to <version>      Non-interactive: set the kernel whose version matches
                            <version> (a `uname -r` style string) as default.

STANDARD FLAGS:
    -h, --help              Show this help and exit
        --version           Print version
    -y, --yes               Non-interactive; auto-confirm (requires --to)
    -n, --dry-run           Print the commands, change nothing
        --log               Tee output to /var/log/linux-skills/
    -v, --verbose           Echo commands as they run
    -q, --quiet             Errors and result only

EXIT CODES:
    0  success
    1  generic failure
    2  usage/flag error
    3  precondition failed (not root for a mutation, or unsupported distro)
    5  dependency missing

EXAMPLES:
    sudo sk-kernel-rollback --list                 # show installed kernels
    sudo sk-kernel-rollback                         # interactively pick + set default
    sudo sk-kernel-rollback --to 5.15.0-91-generic  # set this kernel as default
    sudo sk-kernel-rollback --to 5.14.0-70.13.1.el9_0.x86_64 --yes

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# Populate KERNELS[] with installed kernel version strings (uname -r style),
# newest-mtime last, for the detected family.
KERNELS=()
collect_kernels() {
    KERNELS=()
    local k
    for k in /boot/vmlinuz-*; do
        [[ -e "$k" ]] || continue
        local base="${k##*/vmlinuz-}"
        # Skip rescue images — never a rollback target.
        [[ "$base" == *rescue* ]] && continue
        KERNELS+=("$base")
    done
    (( ${#KERNELS[@]} > 0 )) || die "no kernels found in /boot" 1
}

# Print the current GRUB default kernel version (best-effort, per family).
current_default() {
    detect_distro
    if [[ "$SK_DISTRO_FAMILY" == "rhel" ]] && command -v grubby >/dev/null 2>&1; then
        local p; p="$(grubby --default-kernel 2>/dev/null)"
        printf '%s' "${p##*/vmlinuz-}"
    else
        # Debian: GRUB saved_entry, if any.
        if command -v grub-editenv >/dev/null 2>&1; then
            grub-editenv list 2>/dev/null | sed -n 's/^saved_entry=//p'
        fi
    fi
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
ARGS=()
while (( $# > 0 )); do
    case "$1" in
        --list)   LIST_ONLY=1 ;;
        --to)     TARGET_VERSION="${2:-}"; shift ;;
        --to=*)   TARGET_VERSION="${1#*=}" ;;
        *)        ARGS+=("$1") ;;
    esac
    shift
done
set -- "${ARGS[@]}"
parse_standard_flags "$@"

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_cmd uname
require_family any        # Debian/Ubuntu or RHEL family
detect_distro

RUNNING="$(uname -r)"
collect_kernels
DEFAULT="$(current_default)"

# =============================================================================
# 6. Main logic
# =============================================================================
header "Kernel rollback: $SK_DISTRO_ID ($SK_DISTRO_FAMILY family)"

info "Installed kernels (* = running, > = current GRUB default):"
idx=0
for kv in "${KERNELS[@]}"; do
    mark="  "
    [[ "$kv" == "$RUNNING" ]] && mark="* "
    [[ -n "$DEFAULT" && "$DEFAULT" == *"$kv"* ]] && mark="${mark%? }>"
    printf "    %2d) %s%s\n" "$idx" "$mark" "$kv"
    idx=$((idx + 1))
done
printf "\n"
info "running: ${RUNNING}    default: ${DEFAULT:-<unknown>}"

if (( LIST_ONLY == 1 )); then
    printf "\n"
    info "Read-only. To set a prior kernel default: sudo sk-kernel-rollback --to <version>"
    info "Full procedure: references/grub2-and-kernel-rollback.md"
    exit 0
fi

# ----- choose a target -----
CHOICE=""
if [[ -n "$TARGET_VERSION" ]]; then
    for kv in "${KERNELS[@]}"; do
        [[ "$kv" == "$TARGET_VERSION" ]] && CHOICE="$kv" && break
    done
    [[ -z "$CHOICE" ]] && die "no installed kernel matches '$TARGET_VERSION' (see --list)" 2
else
    if [[ "$YES" == "1" ]]; then
        die "--yes requires --to <version>; refusing to guess a rollback target" 2
    fi
    CHOICE="$(select_one "Set which kernel as the GRUB default?" "${KERNELS[@]}")"
fi

[[ "$CHOICE" == "$RUNNING" ]] \
    && info "note: '$CHOICE' is the running kernel — setting it default makes the current boot persistent."

# ----- mutate: set the default -----
require_root

info "Will set the GRUB2 default kernel to: ${SK_BOLD}${CHOICE}${SK_NC}"
if ! confirm "Make '$CHOICE' the persistent default kernel?" "N"; then
    info "aborted by user"
    exit 0
fi

if [[ "$SK_DISTRO_FAMILY" == "rhel" ]]; then
    require_cmd grubby
    run grubby --set-default "/boot/vmlinuz-${CHOICE}" \
        || die "grubby --set-default failed for $CHOICE" 1
    NEWDEF="$(grubby --default-kernel 2>/dev/null)"
    pass "default kernel set: ${NEWDEF##*/vmlinuz-}"
else
    require_cmd grub-set-default update-grub
    # Resolve the Advanced-options submenu saved-entry id for this kernel so the
    # choice survives regeneration; fall back to a title match if grep finds one.
    CFG="/boot/grub/grub.cfg"
    ENTRY=""
    if [[ -r "$CFG" ]]; then
        ENTRY="$(grep -oE "gnulinux-[^']*${CHOICE}[^']*-advanced-[a-f0-9-]+" "$CFG" | head -n1)"
    fi
    if [[ -n "$ENTRY" ]]; then
        run grub-set-default "$ENTRY" || die "grub-set-default failed" 1
    else
        warn "could not resolve submenu entry id; falling back to index 0 (newest)"
        run grub-set-default 0 || die "grub-set-default failed" 1
    fi
    run update-grub || die "update-grub failed" 1
    pass "default kernel set to '$CHOICE' (saved_entry=${ENTRY:-0})"
fi

_sk_audit "set default kernel -> $CHOICE (family=$SK_DISTRO_FAMILY)"

printf "\n"
info "Next: reboot to verify the box comes up on '$CHOICE' with no menu interaction."
info "Only AFTER a clean reboot, remove/blacklist the bad kernel (see reference §6)."
info "Reference: references/grub2-and-kernel-rollback.md"

exit 0
