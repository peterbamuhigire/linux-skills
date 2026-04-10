#!/usr/bin/env bash
#: Title:       sk-audit
#: Synopsis:    sk-audit [--yes] [--log] [--json]
#: Description: Read-only security audit for Ubuntu/Debian servers. Runs a 14-
#:              section check and produces a PASS/WARN/FAIL report with a score.
#:              Non-destructive — this script observes and reports, never
#:              modifies. Use linux-server-hardening to fix what it finds.
#: Author:      Peter Bamuhigire <techguypeter.com>
#: Contact:     +256784464178
#: Version:     0.2.0

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
SCRIPT_VERSION="0.2.0"

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-audit [OPTIONS]

Read-only 14-section security audit for Ubuntu/Debian servers.

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
    3  precondition failed (not root or not Debian/Ubuntu)

EXAMPLES:
    sudo sk-audit
    sudo sk-audit --log
    sudo sk-audit --yes --quiet

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# Helper: get effective SSH setting (drop-in dir has higher priority)
ssh_setting() {
    local key="$1"
    local val=""
    if [[ -d /etc/ssh/sshd_config.d ]]; then
        val=$(grep -rh "^${key}" /etc/ssh/sshd_config.d/*.conf 2>/dev/null | tail -1 | awk '{print $2}')
    fi
    if [[ -z "$val" ]]; then
        val=$(grep -h "^${key}" /etc/ssh/sshd_config 2>/dev/null | tail -1 | awk '{print $2}')
    fi
    printf '%s' "$val"
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
require_debian

# =============================================================================
# 6. Main logic — 14 audit sections
# =============================================================================

printf "${SK_BOLD}"
printf "==============================================\n"
printf "  Server Security Audit\n"
printf "  Host: %s\n" "$(hostname)"
printf "  IP:   %s\n" "$(hostname -I | awk '{print $1}')"
printf "  Date: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
# shellcheck disable=SC1091
printf "  OS:   %s\n" "$(. /etc/os-release && echo "$PRETTY_NAME")"
printf "==============================================\n"
printf "${SK_NC}\n"

# --- 1. System updates -------------------------------------------------------
header "1. System Updates"
if dpkg -l 2>/dev/null | grep -q unattended-upgrades; then
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

UPDATES=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || true)
if (( UPDATES > 10 )); then
    warn "$UPDATES packages have pending updates"
elif (( UPDATES > 0 )); then
    info "$UPDATES packages have pending updates"
else
    pass "System is fully up to date"
fi

# --- 2. SSH hardening --------------------------------------------------------
header "2. SSH Configuration"

ROOT_LOGIN=$(ssh_setting "PermitRootLogin")
if [[ "$ROOT_LOGIN" == "no" ]]; then
    pass "Root login is disabled"
elif [[ "$ROOT_LOGIN" == "prohibit-password" ]]; then
    warn "Root login allowed with keys only (consider 'no')"
else
    fail "Root login is permitted: $ROOT_LOGIN"
fi

PASS_AUTH=$(ssh_setting "PasswordAuthentication")
if [[ "$PASS_AUTH" == "no" ]]; then
    pass "Password authentication is disabled (key-only)"
else
    warn "Password authentication is ON — consider switching to key-only"
fi

PUBKEY_AUTH=$(ssh_setting "PubkeyAuthentication")
if [[ "$PUBKEY_AUTH" == "yes" || -z "$PUBKEY_AUTH" ]]; then
    pass "Public key authentication is enabled"
else
    fail "Public key authentication is disabled"
fi

MAX_AUTH=$(ssh_setting "MaxAuthTries")
if [[ -n "$MAX_AUTH" && "$MAX_AUTH" -le 4 ]]; then
    pass "MaxAuthTries is set to $MAX_AUTH"
else
    warn "MaxAuthTries is ${MAX_AUTH:-6 (default)} — consider 3-4"
fi

EMPTY_PASS=$(ssh_setting "PermitEmptyPasswords")
if [[ "$EMPTY_PASS" == "no" || -z "$EMPTY_PASS" ]]; then
    pass "Empty passwords are not permitted"
else
    fail "Empty passwords are permitted!"
fi

# --- 3. Firewall -------------------------------------------------------------
header "3. Firewall"
UFW_STATUS=$(ufw status 2>/dev/null | head -1)
if echo "$UFW_STATUS" | grep -q "active"; then
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
    fail "fail2ban is NOT running"
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
if systemctl is-active apache2 &>/dev/null; then
    pass "Apache is running"
    TOKENS=$(grep -rh "^ServerTokens" /etc/apache2/conf-enabled/ /etc/apache2/conf-available/security.conf 2>/dev/null | tail -1 | awk '{print $2}')
    if [[ "$TOKENS" == "Prod" ]]; then
        pass "ServerTokens set to Prod"
    else
        warn "ServerTokens is '${TOKENS:-OS}' — set to 'Prod'"
    fi

    SIGNATURE=$(grep -rh "^ServerSignature" /etc/apache2/conf-enabled/ /etc/apache2/conf-available/security.conf 2>/dev/null | tail -1 | awk '{print $2}')
    if [[ "$SIGNATURE" == "Off" ]]; then
        pass "ServerSignature is Off"
    else
        warn "ServerSignature is '${SIGNATURE:-On}' — set to 'Off'"
    fi
else
    info "Apache is not running"
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
    if systemctl is-active certbot.timer &>/dev/null || systemctl is-active snap.certbot.renew.timer &>/dev/null; then
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
sysctl_check "net.ipv4.conf.all.rp_filter"         "1" "Reverse path filtering enabled"
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

SUDO_USERS=$(grep -E "^sudo:" /etc/group | cut -d: -f4)
info "Users in sudo group: ${SUDO_USERS:-none}"

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

if dpkg -l 2>/dev/null | grep -q "logwatch\|logcheck"; then
    pass "Log monitoring tool installed"
else
    info "No log monitoring tool installed"
fi

if systemctl is-active auditd &>/dev/null; then
    pass "auditd is running"
else
    info "auditd not running (optional)"
fi

# =============================================================================
# Summary
# =============================================================================
print_summary

if (( FAIL_COUNT > 0 )); then
    printf "  ${SK_RED}Action required: %d critical issue(s) found.${SK_NC}\n" "$FAIL_COUNT"
fi
if (( WARN_COUNT > 0 )); then
    printf "  ${SK_YELLOW}%d item(s) could be improved.${SK_NC}\n" "$WARN_COUNT"
fi

exit 0
