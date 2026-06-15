#!/usr/bin/env bash
#: Title:       sk-cifs-mount
#: Synopsis:    sk-cifs-mount [--yes] [--dry-run] [--log] //server/share /mountpoint
#: Description: Mount a CIFS/SMB (Samba/Windows) share safely on Debian/Ubuntu
#:              and RHEL-family hosts. Ensures cifs-utils is installed, builds or
#:              reuses a 0600 credentials file, test-mounts the share, and
#:              optionally writes a persistent /etc/fstab entry with sane
#:              network-mount options (_netdev,nofail,vers=,uid=,gid=). Interactive
#:              by default; ask-before-mutate. See references/cifs-and-network-mounts.md.
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

UNC=""                                  # //server/share  (positional 1)
MOUNTPOINT=""                           # /mnt/share      (positional 2)
CREDENTIALS="${CREDENTIALS:-/root/.smbcredentials}"
SMB_USER="${SMB_USER:-}"                # if set, write a credentials file
SMB_PASS="${SMB_PASS:-}"
SMB_DOMAIN="${SMB_DOMAIN:-}"
MOUNT_UID="${MOUNT_UID:-}"              # local uid to map files to
MOUNT_GID="${MOUNT_GID:-}"
VERS="${VERS:-3.0}"                     # SMB dialect to pin
SEC="${SEC:-}"                          # ntlmssp | krb5 | ... (optional)
PERSIST="${PERSIST:-ask}"              # ask | yes | no — write fstab entry?

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-cifs-mount [OPTIONS] //server/share /mountpoint

Mount a CIFS/SMB (Samba/Windows) share. Installs cifs-utils if missing,
uses (or builds) a 0600 credentials file, test-mounts, and optionally
adds a persistent /etc/fstab entry.

ARGUMENTS:
    //server/share          UNC path (forward slashes) of the share
    /mountpoint             Local directory to mount on (created if absent)

DECISION FLAGS:
    --credentials <file>    Credentials file (default: /root/.smbcredentials)
    --smb-user <name>       Build a credentials file with this username
    --smb-pass <pass>       ...and this password (prompted if --smb-user given
                            without --smb-pass and not under --yes)
    --smb-domain <domain>   Optional AD/workgroup domain for the credentials file
    --uid <id>              Map files to this local uid (e.g. id -u peter)
    --gid <id>              Map files to this local gid
    --vers <ver>            SMB dialect: 3.1.1 | 3.0 | 2.1 | 1.0 (default: 3.0)
    --sec <mech>            Auth mechanism: ntlmssp | ntlmv2 | krb5 | krb5i
    --persist <ask|yes|no>  Write a persistent /etc/fstab entry (default: ask)

STANDARD FLAGS:
    -h, --help              Show this help and exit
        --version           Print version
    -y, --yes               Non-interactive mode
    -n, --dry-run           Print actions, change nothing
        --log               Tee output to /var/log/linux-skills/
    -v, --verbose           Extra diagnostic output
    -q, --quiet             Errors and result only

EXIT CODES:
    0  success
    1  mount failed
    2  usage/flag error
    3  precondition failed (bad creds-file mode, missing args)
    4  user aborted
    5  dependency missing (could not install cifs-utils)

EXAMPLES:
    # Use an existing /root/.smbcredentials, mount, ask about fstab:
    sudo sk-cifs-mount //server2/sambashare /mnt/share

    # Build the credentials file and map files to user peter, persist:
    sudo sk-cifs-mount --smb-user linda --smb-domain WORKGROUP \
         --uid 1000 --gid 1000 --persist yes //nas/media /mnt/media

    # Preview only:
    sudo sk-cifs-mount --dry-run //server/share /mnt/share

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
parse_standard_flags "$@"

POSITIONAL=()
while (( ${#REMAINING_ARGS[@]} > 0 )); do
    case "${REMAINING_ARGS[0]}" in
        --credentials) CREDENTIALS="${REMAINING_ARGS[1]:-}"; REMAINING_ARGS=("${REMAINING_ARGS[@]:2}") ;;
        --smb-user)    SMB_USER="${REMAINING_ARGS[1]:-}";    REMAINING_ARGS=("${REMAINING_ARGS[@]:2}") ;;
        --smb-pass)    SMB_PASS="${REMAINING_ARGS[1]:-}";    REMAINING_ARGS=("${REMAINING_ARGS[@]:2}") ;;
        --smb-domain)  SMB_DOMAIN="${REMAINING_ARGS[1]:-}";  REMAINING_ARGS=("${REMAINING_ARGS[@]:2}") ;;
        --uid)         MOUNT_UID="${REMAINING_ARGS[1]:-}";   REMAINING_ARGS=("${REMAINING_ARGS[@]:2}") ;;
        --gid)         MOUNT_GID="${REMAINING_ARGS[1]:-}";   REMAINING_ARGS=("${REMAINING_ARGS[@]:2}") ;;
        --vers)        VERS="${REMAINING_ARGS[1]:-}";        REMAINING_ARGS=("${REMAINING_ARGS[@]:2}") ;;
        --sec)         SEC="${REMAINING_ARGS[1]:-}";         REMAINING_ARGS=("${REMAINING_ARGS[@]:2}") ;;
        --persist)     PERSIST="${REMAINING_ARGS[1]:-}";     REMAINING_ARGS=("${REMAINING_ARGS[@]:2}") ;;
        --*)           die "unknown option: ${REMAINING_ARGS[0]}" 2 ;;
        *)             POSITIONAL+=("${REMAINING_ARGS[0]}");  REMAINING_ARGS=("${REMAINING_ARGS[@]:1}") ;;
    esac
done

UNC="${POSITIONAL[0]:-}"
MOUNTPOINT="${POSITIONAL[1]:-}"

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_root "$UNC $MOUNTPOINT"
require_family any        # runs on Debian/Ubuntu and the RHEL family

[[ -n "$UNC" ]]        || die "missing //server/share argument (see --help)" 2
[[ -n "$MOUNTPOINT" ]] || die "missing /mountpoint argument (see --help)" 2

# Reject backslash UNC — the single most common mistake.
if [[ "$UNC" == *'\'* || "$UNC" != //* ]]; then
    die "share must be a forward-slash UNC path, e.g. //server/share (got: $UNC)" 2
fi

case "$PERSIST" in ask|yes|no) ;; *) die "--persist must be ask|yes|no" 2 ;; esac

# Ensure the CIFS client is present.
if ! pkg_is_installed cifs-utils; then
    info "cifs-utils not installed"
    if confirm "Install cifs-utils now?" Y; then
        pkg_update
        pkg_install cifs-utils || die "could not install cifs-utils" 5
    else
        die "cifs-utils is required to mount CIFS shares" 5
    fi
fi
require_cmd mount.cifs mount findmnt

# =============================================================================
# 6. Credentials file
# =============================================================================
header "sk-cifs-mount — $UNC -> $MOUNTPOINT"

if [[ -n "$SMB_USER" ]]; then
    # Build/refresh a 0600 credentials file from the supplied user.
    if [[ -z "$SMB_PASS" ]]; then
        if [[ "$YES" == "1" ]]; then
            die "--smb-user given without --smb-pass under --yes" 2
        fi
        printf "  ${SK_CYAN}SMB password for %s${SK_NC} (input hidden): " "$SMB_USER" >&2
        IFS= read -rs SMB_PASS; printf '\n' >&2
        [[ -n "$SMB_PASS" ]] || die "empty password" 2
    fi
    info "writing credentials file: $CREDENTIALS"
    if [[ "$DRY_RUN" != "1" ]]; then
        [[ -e "$CREDENTIALS" ]] && backup_file "$CREDENTIALS" >/dev/null
        {
            printf 'username=%s\n' "$SMB_USER"
            printf 'password=%s\n' "$SMB_PASS"
            [[ -n "$SMB_DOMAIN" ]] && printf 'domain=%s\n' "$SMB_DOMAIN"
        } | atomic_write "$CREDENTIALS"
        run chown root:root "$CREDENTIALS"
        run chmod 600 "$CREDENTIALS"
    fi
fi

[[ -f "$CREDENTIALS" ]] || die "credentials file not found: $CREDENTIALS (pass --smb-user to create one, or --credentials)" 3

# Enforce 0600 on the credentials file — it holds a cleartext password.
if [[ "$DRY_RUN" != "1" ]]; then
    mode="$(stat -c '%a' "$CREDENTIALS" 2>/dev/null)"
    if [[ "$mode" != "600" ]]; then
        fail "$CREDENTIALS has mode $mode, must be 600 (cleartext password is exposed)"
        die "credentials file permissions" 3
    fi
    pass "credentials file mode 0600 verified"
fi

# =============================================================================
# 7. Build mount options + mount
# =============================================================================
OPTS="credentials=${CREDENTIALS}"
[[ -n "$VERS" ]]      && OPTS+=",vers=${VERS}"
[[ -n "$SEC" ]]       && OPTS+=",sec=${SEC}"
[[ -n "$MOUNT_UID" ]] && OPTS+=",uid=${MOUNT_UID}"
[[ -n "$MOUNT_GID" ]] && OPTS+=",gid=${MOUNT_GID}"
OPTS+=",iocharset=utf8"

info "mount options: $OPTS"

run mkdir -p "$MOUNTPOINT"

if findmnt -rn "$MOUNTPOINT" >/dev/null 2>&1; then
    warn "$MOUNTPOINT is already a mountpoint; unmount it first if you want to remount"
else
    if ! confirm "Test-mount $UNC on $MOUNTPOINT now?" Y; then
        die "user aborted" 4
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        info "DRY-RUN would: mount -t cifs -o $OPTS $UNC $MOUNTPOINT"
    else
        if mount -t cifs -o "$OPTS" "$UNC" "$MOUNTPOINT"; then
            pass "mounted $UNC on $MOUNTPOINT"
            _sk_audit "mounted $UNC on $MOUNTPOINT (opts: $OPTS)"
            findmnt "$MOUNTPOINT" || true
        else
            fail "mount failed — common causes: wrong vers= (try 3.0/2.1), bad credentials, or sec= mismatch"
            info "see references/cifs-and-network-mounts.md section 10 (Troubleshooting)"
            die "mount -t cifs failed" 1
        fi
    fi
fi

# =============================================================================
# 8. Persist in /etc/fstab
# =============================================================================
FSTAB_OPTS="${OPTS},_netdev,nofail,x-systemd.automount"
FSTAB_LINE="${UNC}  ${MOUNTPOINT}  cifs  ${FSTAB_OPTS}  0  0"

want_persist=0
case "$PERSIST" in
    yes) want_persist=1 ;;
    no)  want_persist=0 ;;
    ask)
        if [[ "$YES" == "1" ]]; then
            want_persist=0      # do not silently edit fstab under --yes
        elif confirm "Add a persistent /etc/fstab entry?" N; then
            want_persist=1
        fi
        ;;
esac

if (( want_persist )); then
    if grep -qF "$MOUNTPOINT" /etc/fstab 2>/dev/null; then
        warn "an /etc/fstab entry already references $MOUNTPOINT; leaving it untouched"
    elif confirm_destructive "Append to /etc/fstab:\n    $FSTAB_LINE"; then
        if [[ "$DRY_RUN" == "1" ]]; then
            info "DRY-RUN would append to /etc/fstab: $FSTAB_LINE"
        else
            backup_file /etc/fstab >/dev/null
            printf '%s\n' "$FSTAB_LINE" >> /etc/fstab
            _sk_audit "appended fstab entry for $MOUNTPOINT"
            pass "added /etc/fstab entry"
            info "validate with: sudo mount -a  (then: findmnt $MOUNTPOINT)"
        fi
    fi
else
    info "not persisting to /etc/fstab (mount is for this boot only)"
fi

print_summary
exit 0
