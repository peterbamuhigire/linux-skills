#!/usr/bin/env bash
#: Title:       sk-module-info
#: Synopsis:    sk-module-info [<mod>] [--blacklist <mod>]
#: Description: Read-only kernel-module inspector for Debian/Ubuntu and the
#:              RHEL family. With no argument it lists loaded modules (lsmod);
#:              with a module name it shows `modinfo <mod>`. With --blacklist
#:              <mod> it ONLY PRINTS the exact blacklist + initramfs-rebuild
#:              steps for the detected family (update-initramfs vs dracut) and
#:              never applies them unless the user explicitly confirms.
#:              Non-destructive by default — observes and reports.
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
BLACKLIST_MOD=""

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-module-info [<mod>] [OPTIONS]

Read-only kernel-module inspector. Works on Debian/Ubuntu and the RHEL family;
auto-detects the family via common.sh. Never modifies the system by default.

MODES:
    (no argument)          List all loaded modules (lsmod).
    <mod>                   Show `modinfo <mod>` plus whether it is loaded.
    --blacklist <mod>       PRINT (do not apply) the exact blacklist and
                            initramfs-rebuild steps for the detected family.

STANDARD FLAGS:
    -h, --help              Show this help and exit
        --version           Print version
    -y, --yes               No-op (this script is read-only)
    -n, --dry-run           No-op (this script is read-only)
        --log               Tee output to /var/log/linux-skills/
    -v, --verbose           Extra diagnostic output
    -q, --quiet             Errors and final result only

EXIT CODES:
    0  success
    2  usage error (e.g. --blacklist with no module name)
    5  dependency missing (lsmod not available)

EXAMPLES:
    sk-module-info                      # list loaded modules
    sk-module-info i915                 # modinfo for the i915 driver
    sk-module-info --blacklist nouveau  # print blacklist steps, apply nothing

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

print_blacklist_steps() {
    local mod="$1"
    local conf="/etc/modprobe.d/blacklist-${mod}.conf"
    local rebuild

    detect_distro
    case "$SK_DISTRO_FAMILY" in
        debian) rebuild="sudo update-initramfs -u" ;;
        rhel)   rebuild="sudo dracut -f" ;;
        *)      rebuild="# (unknown family) rebuild the initramfs with your distro's tool" ;;
    esac

    header "Blacklist steps for module: $mod (NOT applied)"
    info "Detected family: ${SK_DISTRO_FAMILY:-unknown}"
    cat <<EOF

  These steps are PRINTED ONLY. Review them, then run them yourself.

  1. Create the blacklist config:

       cat <<'CONF' | sudo tee $conf
       blacklist $mod
       install $mod /bin/true
       CONF

     'blacklist' stops auto-loading by name; 'install $mod /bin/true' also
     defeats loads pulled in as a dependency (the stronger form).

  2. Rebuild the initramfs (required if '$mod' loads at boot):

       $rebuild

  3. Reboot and verify it is gone:

       lsmod | grep $mod        # expect no output

EOF
    warn "SAFETY: blacklisting a storage or network driver can make this host"
    warn "unbootable or unreachable. Confirm console / out-of-band access and a"
    warn "known-good fallback kernel before rebooting."
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
# Pre-scan for --blacklist <mod> (consumes its argument) before the standard
# parser, which would otherwise leave it in REMAINING_ARGS.
_args=()
while (( $# > 0 )); do
    case "$1" in
        --blacklist)
            shift
            [[ $# -gt 0 ]] || { echo "FATAL: --blacklist requires a module name" >&2; exit 2; }
            BLACKLIST_MOD="$1"
            ;;
        --blacklist=*)
            BLACKLIST_MOD="${1#*=}"
            ;;
        *)
            _args+=("$1")
            ;;
    esac
    shift
done

parse_standard_flags "${_args[@]+"${_args[@]}"}"

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_family any        # Debian/Ubuntu or RHEL family; sets SK_DISTRO_FAMILY
require_cmd lsmod

# =============================================================================
# 6. Main logic
# =============================================================================

# --blacklist <mod>: print steps only, never apply.
if [[ -n "$BLACKLIST_MOD" ]]; then
    print_blacklist_steps "$BLACKLIST_MOD"
    header "Result"
    pass "blacklist steps printed for '$BLACKLIST_MOD' (nothing applied)"
    exit 0
fi

# A positional module name → modinfo; otherwise list loaded modules.
TARGET="${REMAINING_ARGS[0]:-}"

if [[ -n "$TARGET" ]]; then
    require_cmd modinfo
    header "Module: $TARGET"
    if lsmod | awk '{print $1}' | grep -qx "$TARGET"; then
        pass "'$TARGET' is currently LOADED"
    else
        info "'$TARGET' is not currently loaded (modinfo still works if installed)"
    fi
    if modinfo "$TARGET" 2>/dev/null; then
        :
    else
        warn "modinfo found no module named '$TARGET'"
    fi
else
    header "Loaded kernel modules (lsmod)"
    lsmod
    if [[ "$VERBOSE" == "1" ]]; then
        info "module count: $(($(lsmod | wc -l) - 1))"
    fi
fi

header "Result"
pass "module inspection complete (read-only)"
exit 0
