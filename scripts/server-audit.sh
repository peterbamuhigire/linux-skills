#!/bin/bash
# =============================================================================
# server-audit.sh — Security Audit Script for Debian/Ubuntu Servers
# =============================================================================
# Non-destructive read-only audit. Checks security posture and reports
# PASS / WARN / FAIL for each item. Does NOT modify anything.
#
# Usage:   sudo ./server-audit.sh
# Output:  Color-coded terminal report + optional log file
#
# Designed for production web servers running Apache + PHP + MySQL/MariaDB.
# Balances security with service delivery — flags real risks, not paranoia.
# =============================================================================

set -u

# --- Colors & Symbols --------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0

pass()  { echo -e "  ${GREEN}[PASS]${NC} $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
warn()  { echo -e "  ${YELLOW}[WARN]${NC} $1"; WARN_COUNT=$((WARN_COUNT + 1)); }
fail()  { echo -e "  ${RED}[FAIL]${NC} $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
info()  { echo -e "  ${CYAN}[INFO]${NC} $1"; }
header(){ echo -e "\n${BOLD}=== $1 ===${NC}"; }

# --- Root check ---------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root (sudo).${NC}"
    exit 1
fi

LOG_FILE=""
if [[ "${1:-}" == "--log" ]]; then
    LOG_FILE="/tmp/server-audit-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee -a "$LOG_FILE") 2>&1
    info "Logging to $LOG_FILE"
fi

echo -e "${BOLD}"
echo "=============================================="
echo "  Server Security Audit"
echo "  Host: $(hostname)"
echo "  IP:   $(hostname -I | awk '{print $1}')"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  OS:   $(. /etc/os-release && echo "$PRETTY_NAME")"
echo "=============================================="
echo -e "${NC}"

# =============================================================================
# 1. SYSTEM UPDATES
# =============================================================================
header "1. System Updates"

if dpkg -l | grep -q unattended-upgrades; then
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
    fail "Automatic updates not configured (/etc/apt/apt.conf.d/20auto-upgrades missing)"
fi

UPDATES=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || true)
if [[ "$UPDATES" -gt 10 ]]; then
    warn "$UPDATES packages have pending updates"
elif [[ "$UPDATES" -gt 0 ]]; then
    info "$UPDATES packages have pending updates"
else
    pass "System is fully up to date"
fi

# =============================================================================
# 2. SSH HARDENING
# =============================================================================
header "2. SSH Configuration"

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DIR="/etc/ssh/sshd_config.d"

# Helper: get effective SSH setting (checks drop-in dir first, then main config)
ssh_setting() {
    local key="$1"
    local val=""
    # Check drop-in configs (higher priority)
    if [[ -d "$SSHD_DIR" ]]; then
        val=$(grep -rh "^${key}" "$SSHD_DIR"/*.conf 2>/dev/null | tail -1 | awk '{print $2}')
    fi
    # Fall back to main config
    if [[ -z "$val" ]]; then
        val=$(grep -h "^${key}" "$SSHD_CONFIG" 2>/dev/null | tail -1 | awk '{print $2}')
    fi
    echo "$val"
}

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

X11FWD=$(ssh_setting "X11Forwarding")
if [[ "$X11FWD" == "no" ]]; then
    pass "X11 forwarding is disabled"
else
    warn "X11 forwarding is enabled"
fi

EMPTY_PASS=$(ssh_setting "PermitEmptyPasswords")
if [[ "$EMPTY_PASS" == "no" || -z "$EMPTY_PASS" ]]; then
    pass "Empty passwords are not permitted"
else
    fail "Empty passwords are permitted!"
fi

# =============================================================================
# 3. FIREWALL
# =============================================================================
header "3. Firewall"

UFW_STATUS=$(ufw status 2>/dev/null | head -1)
if echo "$UFW_STATUS" | grep -q "active"; then
    pass "UFW firewall is active"
    # Check default policy
    UFW_DEFAULT=$(ufw status verbose 2>/dev/null | grep "Default:")
    if echo "$UFW_DEFAULT" | grep -q "deny (incoming)"; then
        pass "Default incoming policy is DENY"
    else
        warn "Default incoming policy is not DENY: $UFW_DEFAULT"
    fi
    # List open ports
    info "Open ports:"
    ufw status | grep "ALLOW" | while read -r line; do
        echo "         $line"
    done
else
    fail "UFW firewall is NOT active"
fi

# =============================================================================
# 4. FAIL2BAN
# =============================================================================
header "4. Fail2Ban"

if systemctl is-active fail2ban &>/dev/null; then
    pass "fail2ban is running"
    JAIL_COUNT=$(fail2ban-client status 2>/dev/null | grep "Number of jail" | awk '{print $NF}')
    if [[ "$JAIL_COUNT" -ge 5 ]]; then
        pass "$JAIL_COUNT jails configured"
    elif [[ "$JAIL_COUNT" -ge 1 ]]; then
        warn "Only $JAIL_COUNT jail(s) — consider adding more (apache, recidive)"
    else
        fail "No jails are active"
    fi
    # Show jails
    JAILS=$(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*://;s/,/ /g')
    info "Active jails: $JAILS"
    # Total bans
    TOTAL_BANNED=$(fail2ban-client status sshd 2>/dev/null | grep "Total banned" | awk '{print $NF}')
    if [[ -n "$TOTAL_BANNED" ]]; then
        info "SSH total bans: $TOTAL_BANNED"
    fi
else
    fail "fail2ban is NOT running"
fi

# =============================================================================
# 5. OPEN PORTS & SERVICES
# =============================================================================
header "5. Open Ports & Services"

info "Listening services:"
ss -tulnp | grep LISTEN | while read -r line; do
    ADDR=$(echo "$line" | awk '{print $5}')
    PROC=$(echo "$line" | awk '{print $7}' | sed 's/.*"\(.*\)".*/\1/')
    echo "         $ADDR  ($PROC)"
done

# Check if MySQL is exposed externally
MYSQL_LISTEN=$(ss -tlnp | grep ":3306" | head -1)
if echo "$MYSQL_LISTEN" | grep -q "0.0.0.0:3306\|\*:3306"; then
    fail "MySQL (3306) is listening on ALL interfaces — bind to 127.0.0.1!"
elif echo "$MYSQL_LISTEN" | grep -q "127.0.0.1:3306"; then
    pass "MySQL is bound to localhost only"
elif [[ -z "$MYSQL_LISTEN" ]]; then
    info "MySQL not detected on port 3306"
fi

# Check MySQL X Protocol
MYSQLX_LISTEN=$(ss -tlnp | grep ":33060" | head -1)
if echo "$MYSQLX_LISTEN" | grep -q "0.0.0.0:33060\|\*:33060"; then
    warn "MySQL X Protocol (33060) is listening on all interfaces — consider disabling or binding to localhost"
fi

# Check Redis exposure
REDIS_LISTEN=$(ss -tlnp | grep ":6379" | head -1)
if echo "$REDIS_LISTEN" | grep -q "0.0.0.0:6379\|\*:6379"; then
    fail "Redis (6379) is listening on ALL interfaces — bind to 127.0.0.1!"
elif echo "$REDIS_LISTEN" | grep -q "127.0.0.1:6379"; then
    pass "Redis is bound to localhost only"
fi

# Check PostgreSQL exposure
PG_LISTEN=$(ss -tlnp | grep ":5432" | head -1)
if echo "$PG_LISTEN" | grep -q "0.0.0.0:5432\|\*:5432"; then
    fail "PostgreSQL (5432) is listening on ALL interfaces!"
elif echo "$PG_LISTEN" | grep -q "127.0.0.1:5432"; then
    pass "PostgreSQL is bound to localhost only"
fi

# =============================================================================
# 6. APACHE SECURITY
# =============================================================================
header "6. Apache Web Server"

if systemctl is-active apache2 &>/dev/null; then
    pass "Apache is running"

    # ServerTokens
    TOKENS=$(grep -rh "^ServerTokens" /etc/apache2/conf-enabled/ /etc/apache2/conf-available/security.conf 2>/dev/null | tail -1 | awk '{print $2}')
    if [[ "$TOKENS" == "Prod" ]]; then
        pass "ServerTokens set to Prod (minimal info)"
    else
        warn "ServerTokens is '${TOKENS:-OS}' — set to 'Prod' to hide version info"
    fi

    # ServerSignature
    SIGNATURE=$(grep -rh "^ServerSignature" /etc/apache2/conf-enabled/ /etc/apache2/conf-available/security.conf 2>/dev/null | tail -1 | awk '{print $2}')
    if [[ "$SIGNATURE" == "Off" ]]; then
        pass "ServerSignature is Off"
    else
        warn "ServerSignature is '${SIGNATURE:-On}' — set to 'Off'"
    fi

    # Check mod_headers
    if apache2ctl -M 2>/dev/null | grep -q "headers_module"; then
        pass "mod_headers is loaded"
    else
        warn "mod_headers is not loaded — needed for security headers"
    fi

    # Check mod_security (optional)
    if apache2ctl -M 2>/dev/null | grep -q "security2_module"; then
        pass "mod_security (WAF) is loaded"
    else
        info "mod_security is not installed (optional, adds WAF layer)"
    fi

    # Check security headers in vhosts (check both enabled and available)
    VHOST_COUNT=$(ls /etc/apache2/sites-enabled/*.conf 2>/dev/null | wc -l)
    HSTS_COUNT=$(grep -rl "Strict-Transport-Security" /etc/apache2/sites-enabled/ /etc/apache2/sites-available/ 2>/dev/null | grep -v ".backup" | sort -u | wc -l)
    XFRAME_COUNT=$(grep -rl "X-Frame-Options" /etc/apache2/sites-enabled/ /etc/apache2/sites-available/ 2>/dev/null | grep -v ".backup" | sort -u | wc -l)
    XCTYPE_COUNT=$(grep -rl "X-Content-Type-Options" /etc/apache2/sites-enabled/ /etc/apache2/sites-available/ 2>/dev/null | grep -v ".backup" | sort -u | wc -l)

    if [[ "$HSTS_COUNT" -ge "$VHOST_COUNT" && "$VHOST_COUNT" -gt 0 ]]; then
        pass "HSTS header set on all $VHOST_COUNT vhosts"
    else
        warn "HSTS header set on $HSTS_COUNT of $VHOST_COUNT vhosts"
    fi

    if [[ "$XFRAME_COUNT" -ge "$VHOST_COUNT" && "$VHOST_COUNT" -gt 0 ]]; then
        pass "X-Frame-Options set on all vhosts"
    else
        warn "X-Frame-Options set on $XFRAME_COUNT of $VHOST_COUNT vhosts"
    fi

    if [[ "$XCTYPE_COUNT" -ge "$VHOST_COUNT" && "$VHOST_COUNT" -gt 0 ]]; then
        pass "X-Content-Type-Options set on all vhosts"
    else
        warn "X-Content-Type-Options set on $XCTYPE_COUNT of $VHOST_COUNT vhosts"
    fi
else
    info "Apache is not running"
fi

# =============================================================================
# 7. PHP SECURITY
# =============================================================================
header "7. PHP Configuration"

if command -v php &>/dev/null; then
    PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)
    info "PHP version: $PHP_VER"

    php_check() {
        local key="$1" expected="$2" label="$3"
        local val
        val=$(php -r "echo ini_get('$key');" 2>/dev/null)
        # Normalize: empty string and "0" both mean "off" for boolean settings
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

    php_check "expose_php"              ""   "PHP version not exposed in headers"
    php_check "display_errors"          ""   "Display errors is off"
    php_check "allow_url_include"       ""   "Remote file inclusion disabled"
    php_check "session.cookie_httponly"  "1"  "Session cookies are httponly"
    php_check "session.cookie_secure"   "1"  "Session cookies require HTTPS"
    php_check "session.use_strict_mode" "1"  "Strict session mode enabled"

    # Check disable_functions
    DISABLED=$(php -r "echo ini_get('disable_functions');" 2>/dev/null)
    if [[ -n "$DISABLED" ]]; then
        pass "Dangerous functions are disabled"
    else
        warn "No functions disabled — consider disabling exec, system, passthru, etc."
    fi

    # Check open_basedir
    BASEDIR=$(php -r "echo ini_get('open_basedir');" 2>/dev/null)
    if [[ -n "$BASEDIR" ]]; then
        pass "open_basedir is set: $BASEDIR"
    else
        info "open_basedir is not set (optional, can restrict PHP file access)"
    fi
else
    info "PHP is not installed"
fi

# =============================================================================
# 8. SSL/TLS CERTIFICATES
# =============================================================================
header "8. SSL/TLS Certificates"

if command -v certbot &>/dev/null; then
    pass "certbot is installed"
    # Check cert expiry
    CERTS=$(certbot certificates 2>/dev/null | grep -A3 "Certificate Name:" | grep "Expiry Date:" || true)
    if [[ -n "$CERTS" ]]; then
        while IFS= read -r line; do
            DAYS=$(echo "$line" | grep -o '[0-9]* days' | awk '{print $1}')
            CERT_NAME=$(echo "$line" | grep -o "VALID:.*" || echo "")
            if [[ -n "$DAYS" && "$DAYS" -lt 14 ]]; then
                fail "Certificate expires in $DAYS days! $CERT_NAME"
            elif [[ -n "$DAYS" && "$DAYS" -lt 30 ]]; then
                warn "Certificate expires in $DAYS days $CERT_NAME"
            elif [[ -n "$DAYS" ]]; then
                pass "Certificate valid for $DAYS days"
            fi
        done <<< "$CERTS"
    fi
    # Check renewal timer
    if systemctl is-active certbot.timer &>/dev/null || systemctl is-active snap.certbot.renew.timer &>/dev/null; then
        pass "Certificate auto-renewal timer is active"
    else
        # Check cron instead
        if crontab -l 2>/dev/null | grep -q certbot || ls /etc/cron.d/certbot 2>/dev/null; then
            pass "Certificate auto-renewal via cron"
        else
            warn "No certbot renewal timer or cron found"
        fi
    fi
else
    info "certbot not installed"
fi

# =============================================================================
# 9. KERNEL HARDENING (sysctl)
# =============================================================================
header "9. Kernel Hardening"

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

sysctl_check "kernel.randomize_va_space"           "2" "ASLR is fully enabled"
sysctl_check "kernel.dmesg_restrict"               "1" "Kernel logs restricted to root"
sysctl_check "net.ipv4.tcp_syncookies"             "1" "TCP SYN cookies enabled"
sysctl_check "net.ipv4.conf.all.accept_redirects"  "0" "ICMP redirects rejected"
sysctl_check "net.ipv4.conf.all.send_redirects"    "0" "ICMP redirect sending disabled"
sysctl_check "net.ipv4.conf.all.rp_filter"         "1" "Reverse path filtering enabled"
sysctl_check "net.ipv4.conf.default.rp_filter"     "1" "Default reverse path filtering"
sysctl_check "net.ipv4.conf.all.accept_source_route" "0" "Source routing disabled"
sysctl_check "net.ipv4.conf.all.log_martians"      "1" "Martian packets logged"
sysctl_check "net.ipv6.conf.all.accept_redirects"  "0" "IPv6 redirects rejected"

# Check if a hardening file exists
if ls /etc/sysctl.d/99-*.conf &>/dev/null; then
    pass "Custom sysctl hardening file exists"
else
    warn "No custom sysctl hardening file in /etc/sysctl.d/"
fi

# =============================================================================
# 10. USER ACCOUNTS
# =============================================================================
header "10. User Accounts"

# Check for users with UID 0 besides root
UID0=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' /etc/passwd)
if [[ -z "$UID0" ]]; then
    pass "No extra UID-0 accounts (only root)"
else
    fail "Extra UID-0 accounts found: $UID0"
fi

# Check for users with empty passwords (not locked/disabled service accounts)
EMPTY_PW=$(awk -F: '$2 == "" {print $1}' /etc/shadow 2>/dev/null | head -5)
if [[ -z "$EMPTY_PW" ]]; then
    pass "No accounts with empty passwords"
else
    fail "Accounts with EMPTY passwords: $EMPTY_PW"
fi

# Check sudo group members
SUDO_USERS=$(grep -E "^sudo:" /etc/group | cut -d: -f4)
info "Users in sudo group: ${SUDO_USERS:-none}"

# =============================================================================
# 11. FILE PERMISSIONS
# =============================================================================
header "11. Critical File Permissions"

check_perms() {
    local file="$1" max_perm="$2" label="$3"
    if [[ -f "$file" ]]; then
        PERM=$(stat -c %a "$file")
        if [[ "$PERM" -le "$max_perm" ]]; then
            pass "$label ($file is $PERM)"
        else
            warn "$label ($file is $PERM, should be $max_perm or less)"
        fi
    fi
}

check_perms "/etc/shadow"          640 "Shadow file permissions"
check_perms "/etc/gshadow"         640 "Gshadow file permissions"
check_perms "/etc/passwd"          644 "Passwd file permissions"
check_perms "/etc/ssh/sshd_config" 644 "SSHD config permissions"

# Check for world-writable files in web root
WWW_WRITABLE=$(find /var/www -type f -perm -0002 2>/dev/null | wc -l)
if [[ "$WWW_WRITABLE" -eq 0 ]]; then
    pass "No world-writable files in /var/www"
else
    warn "$WWW_WRITABLE world-writable file(s) found in /var/www"
fi

# =============================================================================
# 12. BACKUPS
# =============================================================================
header "12. Backups"

# Check for MySQL backup script
if [[ -f /usr/local/bin/mysql-backup.sh ]] || [[ -f "$HOME/scripts/mysql-backup.sh" ]] || crontab -l 2>/dev/null | grep -q "mysql-backup\|backup"; then
    pass "Backup script/cron detected"
else
    warn "No backup script or cron found"
fi

# Check rclone (Google Drive)
if command -v rclone &>/dev/null; then
    pass "rclone is installed (remote backup capability)"
else
    info "rclone not installed"
fi

# Check recent backup files
RECENT_BACKUP=$(find /home/*/backups /root/backups /var/backups -name "*.tar.gz" -mtime -2 2>/dev/null | head -1)
if [[ -n "$RECENT_BACKUP" ]]; then
    pass "Recent backup found (last 48h)"
else
    warn "No recent backup files found (last 48h)"
fi

# =============================================================================
# 13. PHPMYADMIN
# =============================================================================
header "13. phpMyAdmin"

PMA_DIR=$(find /var/www -type d -name "phpmyadmin" 2>/dev/null | head -1)
if [[ -n "$PMA_DIR" ]]; then
    info "phpMyAdmin found at $PMA_DIR"

    # Check if config exists
    if [[ -f "$PMA_DIR/config.inc.php" ]]; then
        # Check blowfish secret
        if grep -q "blowfish_secret.*=.*'.\{32,\}'" "$PMA_DIR/config.inc.php" 2>/dev/null; then
            pass "Blowfish secret is configured (32+ chars)"
        else
            warn "Blowfish secret may be weak or missing"
        fi
    else
        info "No config.inc.php (using defaults)"
    fi

    # Check if behind IP restriction
    PMA_VHOST=$(grep -rl "phpmyadmin" /etc/apache2/sites-enabled/ 2>/dev/null | head -1)
    if [[ -n "$PMA_VHOST" ]]; then
        if grep -q "Require ip\|Allow from" "$PMA_VHOST" 2>/dev/null; then
            pass "phpMyAdmin has IP-based access restrictions"
        else
            warn "phpMyAdmin is publicly accessible — consider IP restrictions"
        fi
    fi

    # Check for production banner
    if grep -q "PRODUCTION\|STAGING\|DEVELOPMENT" "$PMA_DIR/templates/login/header.twig" 2>/dev/null; then
        pass "Login page has server identification banner"
    else
        info "No server identification banner on login page"
    fi
else
    info "phpMyAdmin not found"
fi

# =============================================================================
# 14. INTEGRITY & MONITORING
# =============================================================================
header "14. Integrity & Monitoring"

if command -v aide &>/dev/null; then
    pass "AIDE (file integrity checker) is installed"
else
    info "AIDE not installed (optional: detects unauthorized file changes)"
fi

if dpkg -l | grep -q "logwatch\|logcheck"; then
    pass "Log monitoring tool installed"
else
    info "No log monitoring tool (logwatch/logcheck) installed"
fi

# Check if auditd is running
if systemctl is-active auditd &>/dev/null; then
    pass "auditd is running"
else
    info "auditd not running (optional: tracks system calls and file access)"
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo -e "${BOLD}=============================================="
echo "  AUDIT SUMMARY"
echo "==============================================${NC}"
echo -e "  ${GREEN}PASS: $PASS_COUNT${NC}"
echo -e "  ${YELLOW}WARN: $WARN_COUNT${NC}"
echo -e "  ${RED}FAIL: $FAIL_COUNT${NC}"
TOTAL=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT))
if [[ "$TOTAL" -gt 0 ]]; then
    SCORE=$(( (PASS_COUNT * 100) / TOTAL ))
    echo -e "  ${BOLD}Score: ${SCORE}%${NC}"
fi
echo ""

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo -e "${RED}  Action required: $FAIL_COUNT critical issue(s) found.${NC}"
fi
if [[ "$WARN_COUNT" -gt 0 ]]; then
    echo -e "${YELLOW}  $WARN_COUNT item(s) could be improved.${NC}"
fi

if [[ -n "$LOG_FILE" ]]; then
    echo ""
    echo -e "  Log saved to: $LOG_FILE"
fi
echo ""
