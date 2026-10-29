#!/usr/bin/env bash
#: Title:       sk-audit
#: Synopsis:    sk-audit [--yes] [--log] [--json]
#: Description: Read-only security audit for Debian/Ubuntu and RHEL-family
#:              (Fedora, RHEL, Rocky, Alma) servers. Runs a 14-section check and
#:              produces a PASS/WARN/FAIL report with a score. Non-destructive —
#:              this script observes and reports, never modifies. Family-specific
#:              checks (updates, firewall, Apache, admin group) auto-detect via
#:              common.sh. Use linux-server-hardening to fix what it finds.
#: Author:      Peter Bamuhigire <techguypeter.com>
#: Contact:     +256784464178
#: Version:     0.3.1

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
# read by common.sh standard flag parser
# shellcheck disable=SC2034
SCRIPT_VERSION="0.3.1"

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    # called by common.sh flag parser
    # shellcheck disable=SC2317
    cat <<'EOF'
Usage: sk-audit [OPTIONS]

Read-only 14-section security audit for Debian/Ubuntu and RHEL-family
(Fedora, RHEL, Rocky, Alma) servers. Family-specific checks auto-detect.

Checks: system updates, SSH hardening, firewall, fail2ban, open ports,
Apache, PHP, SSL certificates, kernel sysctl hardening, user accounts,
file permissions, backup health, phpMyAdmin, and AIDE/auditd/logwatch.

Produces a PASS/WARN/FAIL report with a score. Never modifies the system.
To fix findings, use linux-server-hardening.

STANDARD FLAGS:
    -h, --help          Show this help and exit
        --version       Print version
    -y, --yes           Non-interactive mode
    -n, --dry-run       No-op (this script is already read-only)
        --log           Tee output to /var/log/linux-skills/
        --json          (Not yet implemented — reserved for future use)
    -v, --verbose       Extra diagnostic output
    -q, --quiet         Errors and final result only

EXIT CODES:
    0  success (audit completed, regardless of findings)
    1  generic failure
    3  precondition failed (not root, or unsupported distro)

EXAMPLES:
    sudo sk-audit
    sudo sk-audit --log
    sudo sk-audit --yes --quiet

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# Parse OpenSSH's effective configuration, never reconstruct Include/Match order.
# SSH_EFFECTIVE is populated once by sshd -T in the SSH section below.
ssh_setting() {
    local key="${1,,}"
    awk -v key="$key" '$1 == key { print $2; exit }' <<< "$SSH_EFFECTIVE"
}

sysctl_check() {
    local key="$1" expected="$2" label="$3"
    local val
    val=$(sysctl -n "$key" 2>/dev/null)
    if [[ "$val" == "$expected" ]]; then
        pass "$label ($key = $val)"
    else
        warn "$label ($key = $val, recommended: $expected)"
    fi
}

php_check() {
    local key="$1" expected="$2" label="$3"
    local val
    val=$(php -r "echo ini_get('$key');" 2>/dev/null)
    if [[ "$val" == "$expected" ]]; then
        pass "$label"
    elif [[ -z "$val" && "$expected" == "0" ]]; then
        pass "$label"
    elif [[ "$val" == "0" && -z "$expected" ]]; then
        pass "$label"
    else
        warn "$label ($key = '${val:-off}', recommended: '$expected')"
    fi
}

check_perms() {
    local file="$1" max_perm="$2" label="$3"
    if [[ -f "$file" ]]; then
        local perm
        perm=$(stat -c %a "$file")
        if (( 10#$perm <= 10#$max_perm )); then
            pass "$label ($file is $perm)"
        else
            warn "$label ($file is $perm, should be $max_perm or less)"
        fi
    fi
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
parse_standard_flags "$@"

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_root
require_family any        # Debian/Ubuntu or RHEL family; sets SK_DISTRO_FAMILY

# =============================================================================
# 6. Main logic — 14 audit sections
# =============================================================================

printf "%s" "$SK_BOLD"
printf "==============================================\n"
printf "  Server Security Audit\n"
printf "  Host: %s\n" "$(hostname)"
printf "  IP:   %s\n" "$(hostname -I | awk '{print $1}')"
printf "  Date: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
# shellcheck disable=SC1091
printf "  OS:   %s\n" "$(. /etc/os-release && echo "$PRETTY_NAME")"
printf "  Fam:  %s (%s)\n" "$SK_DISTRO_FAMILY" "$SK_PKG"
printf "==============================================\n"
printf "%s\n" "$SK_NC"

# --- 1. System updates -------------------------------------------------------
header "1. System Updates"
UPDATES_KNOWN=0
UPDATES=0
if [[ "$SK_DISTRO_FAMILY" == "debian" ]]; then
    if pkg_is_installed unattended-upgrades; then
        pass "unattended-upgrades is installed"
    else
        fail "unattended-upgrades is NOT installed"
    fi

    if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
        if grep -q 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades; then
            pass "Automatic security updates are enabled"
        else
            warn "auto-upgrades file exists but unattended upgrades may be disabled"
        fi
    else
        fail "Automatic updates not configured"
    fi

    if UPDATE_OUTPUT=$(apt list --upgradable 2>/dev/null); then
        UPDATES=$(printf '%s\n' "$UPDATE_OUTPUT" | grep -c "upgradable" || true)
        UPDATES_KNOWN=1
    fi
else
    # RHEL family: dnf-automatic (dnf4) or dnf5-plugin-automatic (dnf5; the
    # default on Fedora 41+) is the unattended-upgrades equivalent.
    if pkg_is_installed dnf-automatic || pkg_is_installed dnf5-plugin-automatic; then
        pass "dnf-automatic is installed"
    else
        fail "dnf-automatic is NOT installed"
    fi

    if systemctl is-active dnf-automatic.timer &>/dev/null \
       || systemctl is-active dnf-automatic-install.timer &>/dev/null \
       || systemctl is-active dnf5-automatic.timer &>/dev/null; then
        pass "Automatic security updates are enabled (dnf-automatic.timer active)"
    else
        fail "Automatic updates not configured (dnf-automatic.timer inactive)"
    fi

    # `dnf check-update` exits 100 when updates exist; count package lines.
    UPDATE_OUTPUT=$("$SK_PKG" -C -q check-update 2>/dev/null)
    UPDATE_STATUS=$?
    if (( UPDATE_STATUS == 0 || UPDATE_STATUS == 100 )); then
        UPDATES=$(printf '%s\n' "$UPDATE_OUTPUT" | grep -cE '^[A-Za-z0-9]' || true)
        UPDATES_KNOWN=1
    fi
fi

if (( ! UPDATES_KNOWN )); then
    warn "NOT_ASSESSED: cached package update query failed; refresh metadata through the package-management workflow"
elif (( UPDATES > 10 )); then
    warn "$UPDATES packages have pending updates"
elif (( UPDATES > 0 )); then
    info "$UPDATES packages have pending updates"
else
    info "No updates reported by cached metadata; freshness and vulnerability status require vendor verification"
fi

# --- 2. SSH hardening --------------------------------------------------------
header "2. SSH Configuration"

# An absent or stopped SSH server is not a remote-login risk, and reading an
# unconfigured sshd would false-FAIL on empty values. Gate the whole section.
if ! pkg_is_installed openssh-server && [[ ! -f /etc/ssh/sshd_config ]]; then
    info "No SSH server installed — SSH section skipped"
else
    if ! systemctl is-active sshd &>/dev/null && ! systemctl is-active ssh &>/dev/null; then
        info "SSH server present but not running — verify sockets, alternate units and listeners before judging exposure (policy checked below)"
    fi

    SSH_EFFECTIVE=""
    if SSH_EFFECTIVE=$(sshd -T 2>/dev/null) && [[ -n "$SSH_EFFECTIVE" ]]; then
        info "SSH effective default configuration; Match contexts and service command-line overrides require separate verification"
        ROOT_LOGIN=$(ssh_setting "PermitRootLogin")
        case "$ROOT_LOGIN" in
            no) pass "Root login is disabled" ;;
            prohibit-password|without-password) warn "Root login allowed with keys only (consider 'no')" ;;
            "") warn "NOT_ASSESSED: PermitRootLogin unavailable" ;;
            *) fail "Root login is permitted: $ROOT_LOGIN" ;;
        esac

        PASS_AUTH=$(ssh_setting "PasswordAuthentication")
        KBD_AUTH=$(ssh_setting "KbdInteractiveAuthentication")
        if [[ "$PASS_AUTH" == "no" && "$KBD_AUTH" == "no" ]]; then
            pass "Password and keyboard-interactive authentication are disabled"
        else
            warn "Review password/keyboard-interactive authentication and MFA policy: ${PASS_AUTH:-unknown}/${KBD_AUTH:-unknown}"
        fi

        PUBKEY_AUTH=$(ssh_setting "PubkeyAuthentication")
        case "$PUBKEY_AUTH" in
            yes) pass "Public key authentication is enabled" ;;
            no) fail "Public key authentication is disabled" ;;
            *) warn "NOT_ASSESSED: PubkeyAuthentication unavailable or unrecognised" ;;
        esac

        MAX_AUTH=$(ssh_setting "MaxAuthTries")
        if [[ "$MAX_AUTH" =~ ^[0-9]+$ ]] && (( 10#$MAX_AUTH > 0 && 10#$MAX_AUTH <= 4 )); then
            pass "MaxAuthTries is set to $MAX_AUTH"
        else
            warn "MaxAuthTries is ${MAX_AUTH:-unknown} — review the authentication policy"
        fi

        EMPTY_PASS=$(ssh_setting "PermitEmptyPasswords")
        case "$EMPTY_PASS" in
            no) pass "Empty passwords are not permitted" ;;
            yes) fail "Empty passwords are permitted!" ;;
            *) warn "NOT_ASSESSED: PermitEmptyPasswords unavailable" ;;
        esac
    else
        warn "NOT_ASSESSED: sshd -T failed or returned no configuration; no SSH policy passes inferred"
    fi
fi

# --- 3. Firewall -------------------------------------------------------------
header "3. Firewall"
if [[ "$SK_DISTRO_FAMILY" == "debian" ]]; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1)
    if echo "$UFW_STATUS" | grep -qx 'Status: active'; then
        pass "UFW firewall is active"
        UFW_DEFAULT=$(ufw status verbose 2>/dev/null | grep "Default:")
        if echo "$UFW_DEFAULT" | grep -q "deny (incoming)"; then
            pass "Default incoming policy is DENY"
        else
            warn "Default incoming policy is not DENY: $UFW_DEFAULT"
        fi
        info "Open ports:"
        ufw status 2>/dev/null | grep "ALLOW" | while read -r line; do
            printf "         %s\n" "$line"
        done
    else
        fail "UFW firewall is NOT active"
    fi
else
    # RHEL family: firewalld
    if systemctl is-active firewalld &>/dev/null; then
        pass "firewalld is active"
        FW_ZONE=$(firewall-cmd --get-default-zone 2>/dev/null)
        info "Default zone: ${FW_ZONE:-unknown}"
        info "Allowed services/ports:"
        firewall-cmd --list-all 2>/dev/null \
            | grep -E '^\s+(services|ports):' \
            | while read -r line; do printf "         %s\n" "$line"; done
    else
        fail "firewalld is NOT active"
    fi
fi

# --- 4. Fail2Ban -------------------------------------------------------------
header "4. Fail2Ban"
if systemctl is-active fail2ban &>/dev/null; then
    pass "fail2ban is running"
    JAIL_COUNT=$(fail2ban-client status 2>/dev/null | grep "Number of jail" | awk '{print $NF}')
    if [[ "${JAIL_COUNT:-0}" -ge 5 ]]; then
        pass "$JAIL_COUNT jails configured"
    elif [[ "${JAIL_COUNT:-0}" -ge 1 ]]; then
        warn "Only $JAIL_COUNT jail(s) — consider adding more"
    else
        fail "No jails are active"
    fi
else
    # fail2ban guards exposed auth surfaces (SSH, web logins). With no running
    # SSH server and no running web server, its absence is informational.
    if systemctl is-active sshd &>/dev/null || systemctl is-active ssh &>/dev/null \
       || systemctl is-active "$(svc_name apache)" &>/dev/null \
       || systemctl is-active nginx &>/dev/null; then
        fail "fail2ban is NOT running"
    else
        info "fail2ban not running (no SSH/web service exposed — low priority on this host)"
    fi
fi

# --- 5. Open ports & services ------------------------------------------------
header "5. Open Ports & Services"
info "Listening services:"
ss -tulnp 2>/dev/null | grep LISTEN | while read -r line; do
    ADDR=$(echo "$line" | awk '{print $5}')
    PROC=$(echo "$line" | awk '{print $7}' | sed 's/.*"\(.*\)".*/\1/')
    printf "         %s  (%s)\n" "$ADDR" "$PROC"
done

MYSQL_LISTEN=$(ss -tlnp 2>/dev/null | grep ":3306" | head -1)
if echo "$MYSQL_LISTEN" | grep -q "0.0.0.0:3306\|\*:3306"; then
    fail "MySQL (3306) is listening on ALL interfaces — bind to 127.0.0.1!"
elif echo "$MYSQL_LISTEN" | grep -q "127.0.0.1:3306"; then
    pass "MySQL is bound to localhost only"
elif [[ -z "$MYSQL_LISTEN" ]]; then
    info "MySQL not detected on port 3306"
fi

REDIS_LISTEN=$(ss -tlnp 2>/dev/null | grep ":6379" | head -1)
if echo "$REDIS_LISTEN" | grep -q "0.0.0.0:6379\|\*:6379"; then
    fail "Redis (6379) is listening on ALL interfaces — bind to 127.0.0.1!"
elif echo "$REDIS_LISTEN" | grep -q "127.0.0.1:6379"; then
    pass "Redis is bound to localhost only"
fi

PG_LISTEN=$(ss -tlnp 2>/dev/null | grep ":5432" | head -1)
if echo "$PG_LISTEN" | grep -q "0.0.0.0:5432\|\*:5432"; then
    fail "PostgreSQL (5432) is listening on ALL interfaces!"
elif echo "$PG_LISTEN" | grep -q "127.0.0.1:5432"; then
    pass "PostgreSQL is bound to localhost only"
fi

# --- 6. Apache security ------------------------------------------------------
header "6. Apache Web Server"
APACHE_SVC="$(svc_name apache)"            # apache2 (debian) / httpd (rhel)
if [[ "$SK_DISTRO_FAMILY" == "debian" ]]; then
    APACHE_CONF=(/etc/apache2/conf-enabled/ /etc/apache2/conf-available/security.conf)
else
    APACHE_CONF=(/etc/httpd/conf.d/ /etc/httpd/conf/httpd.conf)
fi
if systemctl is-active "$APACHE_SVC" &>/dev/null; then
    pass "Apache ($APACHE_SVC) is running"
    TOKENS=$(grep -rh "^ServerTokens" "${APACHE_CONF[@]}" 2>/dev/null | tail -1 | awk '{print $2}')
    if [[ "$TOKENS" == "Prod" ]]; then
        pass "ServerTokens set to Prod"
    else
        warn "ServerTokens is '${TOKENS:-OS}' — set to 'Prod'"
    fi

    SIGNATURE=$(grep -rh "^ServerSignature" "${APACHE_CONF[@]}" 2>/dev/null | tail -1 | awk '{print $2}')
    if [[ "$SIGNATURE" == "Off" ]]; then
        pass "ServerSignature is Off"
    else
        warn "ServerSignature is '${SIGNATURE:-On}' — set to 'Off'"
    fi
else
    info "Apache ($APACHE_SVC) is not running"
fi

# --- 7. PHP security ---------------------------------------------------------
header "7. PHP Configuration"
if command -v php &>/dev/null; then
    PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)
    info "PHP version: $PHP_VER"
    php_check "expose_php"              ""   "PHP version not exposed in headers"
    php_check "display_errors"          ""   "Display errors is off"
    php_check "allow_url_include"       ""   "Remote file inclusion disabled"
    php_check "session.cookie_httponly"  "1"  "Session cookies are httponly"
    php_check "session.cookie_secure"   "1"  "Session cookies require HTTPS"
    php_check "session.use_strict_mode" "1"  "Strict session mode enabled"

    DISABLED=$(php -r "echo ini_get('disable_functions');" 2>/dev/null)
    if [[ -n "$DISABLED" ]]; then
        pass "Dangerous functions are disabled"
    else
        warn "No functions disabled — consider disabling exec, system, passthru, etc."
    fi
else
    info "PHP is not installed"
fi

# --- 8. SSL/TLS certificates -------------------------------------------------
header "8. SSL/TLS Certificates"
if command -v certbot &>/dev/null; then
    pass "certbot is installed"
    CERTS=$(certbot certificates 2>/dev/null | grep "Expiry Date:" || true)
    if [[ -n "$CERTS" ]]; then
        while IFS= read -r line; do
            DAYS=$(echo "$line" | grep -o '[0-9]* days' | awk '{print $1}')
            if [[ -n "$DAYS" && "$DAYS" -lt 14 ]]; then
                fail "Certificate expires in $DAYS days!"
            elif [[ -n "$DAYS" && "$DAYS" -lt 30 ]]; then
                warn "Certificate expires in $DAYS days"
            elif [[ -n "$DAYS" ]]; then
                pass "Certificate valid for $DAYS days"
            fi
        done <<< "$CERTS"
    fi
    if systemctl is-active certbot.timer &>/dev/null \
       || systemctl is-active certbot-renew.timer &>/dev/null \
       || systemctl is-active snap.certbot.renew.timer &>/dev/null; then
        pass "Certificate auto-renewal timer is active"
    fi
else
    info "certbot not installed"
fi

# --- 9. Kernel hardening -----------------------------------------------------
header "9. Kernel Hardening"
sysctl_check "kernel.randomize_va_space"           "2" "ASLR is fully enabled"
sysctl_check "kernel.dmesg_restrict"               "1" "Kernel logs restricted to root"
sysctl_check "net.ipv4.tcp_syncookies"             "1" "TCP SYN cookies enabled"
sysctl_check "net.ipv4.conf.all.accept_redirects"  "0" "ICMP redirects rejected"
sysctl_check "net.ipv4.conf.all.send_redirects"    "0" "ICMP redirect sending disabled"
# rp_filter takes effect as max(conf.all, conf.<iface>); some distros (Fedora)
# set it per-interface via conf.default, so checking conf.all alone false-WARNs.
rp_eff=$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null || echo 0)
for _rf in /proc/sys/net/ipv4/conf/*/rp_filter; do
    _ifn=$(basename "$(dirname "$_rf")")
    [[ "$_ifn" == "lo" || "$_ifn" == "all" ]] && continue
    _v=$(cat "$_rf" 2>/dev/null || echo 0)
    (( _v > rp_eff )) && rp_eff=$_v
done
if (( rp_eff >= 1 )); then
    pass "Reverse path filtering enabled (effective rp_filter = $rp_eff)"
else
    warn "Reverse path filtering disabled (no interface has rp_filter >= 1, recommended: 1)"
fi
sysctl_check "net.ipv4.conf.all.accept_source_route" "0" "Source routing disabled"
sysctl_check "net.ipv4.conf.all.log_martians"      "1" "Martian packets logged"
sysctl_check "net.ipv6.conf.all.accept_redirects"  "0" "IPv6 redirects rejected"

if ls /etc/sysctl.d/99-*.conf &>/dev/null; then
    pass "Custom sysctl hardening file exists"
else
    warn "No custom sysctl hardening file in /etc/sysctl.d/"
fi

# --- 10. User accounts -------------------------------------------------------
header "10. User Accounts"
UID0=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' /etc/passwd)
if [[ -z "$UID0" ]]; then
    pass "No extra UID-0 accounts (only root)"
else
    fail "Extra UID-0 accounts found: $UID0"
fi

EMPTY_PW=$(awk -F: '$2 == "" {print $1}' /etc/shadow 2>/dev/null | head -5)
if [[ -z "$EMPTY_PW" ]]; then
    pass "No accounts with empty passwords"
else
    fail "Accounts with EMPTY passwords: $EMPTY_PW"
fi

# Admin group differs by family: 'sudo' on Debian/Ubuntu, 'wheel' on RHEL
ADMIN_GROUP="sudo"; [[ "$SK_DISTRO_FAMILY" == "rhel" ]] && ADMIN_GROUP="wheel"
SUDO_USERS=$(grep -E "^${ADMIN_GROUP}:" /etc/group | cut -d: -f4)
info "Users in ${ADMIN_GROUP} group: ${SUDO_USERS:-none}"

# --- 11. File permissions ----------------------------------------------------
header "11. Critical File Permissions"
check_perms "/etc/shadow"          640 "Shadow file permissions"
check_perms "/etc/gshadow"         640 "Gshadow file permissions"
check_perms "/etc/passwd"          644 "Passwd file permissions"
check_perms "/etc/ssh/sshd_config" 644 "SSHD config permissions"

WWW_WRITABLE=$(find /var/www -type f -perm -0002 2>/dev/null | wc -l)
if [[ "$WWW_WRITABLE" -eq 0 ]]; then
    pass "No world-writable files in /var/www"
else
    warn "$WWW_WRITABLE world-writable file(s) found in /var/www"
fi

# --- 12. Backups -------------------------------------------------------------
header "12. Backups"
if [[ -f /usr/local/bin/sk-mysql-backup ]] || [[ -f /usr/local/sbin/mysql-backup.sh ]] || [[ -f "$HOME/scripts/mysql-backup.sh" ]] || crontab -l 2>/dev/null | grep -q "mysql-backup\|backup"; then
    pass "Backup script/cron detected"
else
    warn "No backup script or cron found"
fi

if command -v rclone &>/dev/null; then
    pass "rclone is installed (remote backup capability)"
else
    info "rclone not installed"
fi

RECENT_BACKUP=$(find /home/*/backups /root/backups /var/backups -name "*.gpg" -mtime -2 2>/dev/null | head -1)
if [[ -n "$RECENT_BACKUP" ]]; then
    pass "Recent backup found (last 48h)"
else
    warn "No recent backup files found (last 48h)"
fi

# --- 13. phpMyAdmin ----------------------------------------------------------
header "13. phpMyAdmin"
PMA_DIR=$(find /var/www -type d -name "phpmyadmin" 2>/dev/null | head -1)
if [[ -n "$PMA_DIR" ]]; then
    info "phpMyAdmin found at $PMA_DIR"
    if [[ -f "$PMA_DIR/config.inc.php" ]]; then
        if grep -q "blowfish_secret.*=.*'.\{32,\}'" "$PMA_DIR/config.inc.php" 2>/dev/null; then
            pass "Blowfish secret is configured (32+ chars)"
        else
            warn "Blowfish secret may be weak or missing"
        fi
    fi
else
    info "phpMyAdmin not found"
fi

# --- 14. Integrity & monitoring ----------------------------------------------
header "14. Integrity & Monitoring"
if command -v aide &>/dev/null; then
    pass "AIDE (file integrity checker) is installed"
else
    info "AIDE not installed (optional)"
fi

if pkg_is_installed logwatch || pkg_is_installed logcheck; then
    pass "Log monitoring tool installed"
else
    info "No log monitoring tool installed"
fi

if systemctl is-active auditd &>/dev/null; then
    pass "auditd is running"
else
    info "auditd not running (optional)"
fi

# Mandatory access control — SELinux (RHEL) or AppArmor (Debian/Ubuntu)
if [[ "$SK_DISTRO_FAMILY" == "rhel" ]]; then
    if command -v getenforce &>/dev/null; then
        MODE=$(getenforce 2>/dev/null)
        if [[ "$MODE" == "Enforcing" ]]; then
            pass "SELinux is Enforcing"
        elif [[ "$MODE" == "Permissive" ]]; then
            warn "SELinux is Permissive (logging only — set to Enforcing)"
        else
            fail "SELinux is Disabled"
        fi
    else
        warn "SELinux tools not found (expected on the RHEL family)"
    fi
else
    if command -v aa-status &>/dev/null && aa-status --enabled 2>/dev/null; then
        pass "AppArmor is enabled"
    else
        warn "AppArmor not enabled"
    fi
fi

# =============================================================================
# Summary
# =============================================================================
print_summary

# counter is initialised by common.sh

# shellcheck disable=SC2153
if (( FAIL_COUNT > 0 )); then
    printf "  ${SK_RED}Action required: %d critical issue(s) found.${SK_NC}\n" "$FAIL_COUNT"
fi
if (( WARN_COUNT > 0 )); then
    printf "  ${SK_YELLOW}%d item(s) could be improved.${SK_NC}\n" "$WARN_COUNT"
fi

exit 0
