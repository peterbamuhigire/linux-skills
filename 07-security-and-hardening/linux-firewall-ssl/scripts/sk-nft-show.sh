#!/usr/bin/env bash
#: Title:       sk-nft-show
#: Synopsis:    sk-nft-show [--json] [--log]
#: Description: Read-only view of the raw netfilter layer on Debian/Ubuntu and
#:              RHEL-family hosts. Reports the active front-end (ufw/firewalld),
#:              the live nftables ruleset, the iptables backend mode
#:              (nft shim vs legacy), persistence state, and the main IP routing
#:              table. Non-destructive — observes only, never modifies. Use it
#:              before sk-nft-apply or when debugging why a front-end rule is
#:              (not) taking effect. See references/nftables-and-iptables.md.
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

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-nft-show [OPTIONS]

Read-only view of the raw netfilter layer (nftables/iptables) plus the active
firewall front-end and the IP routing table. Works on Debian/Ubuntu and the
RHEL family; auto-detects via common.sh. Never modifies the system.

Reports:
  - active front-end (ufw / firewalld) and whether it owns the ruleset
  - iptables backend mode (iptables-nft shim vs legacy)
  - live `nft list ruleset`
  - persistence state (nftables.service, netfilter-persistent, config files)
  - the main IP routing table (`ip route`)

STANDARD FLAGS:
    -h, --help          Show this help and exit
        --version       Print version
    -y, --yes           No-op (this script is already read-only)
    -n, --dry-run       No-op (this script is already read-only)
        --log           Tee output to /var/log/linux-skills/
        --json          (Reserved — not yet implemented)
    -v, --verbose       Extra diagnostic output
    -q, --quiet         Errors and final result only

EXIT CODES:
    0  success
    3  precondition failed (not root, or unsupported distro)
    5  dependency missing (no nft and no iptables)

EXAMPLES:
    sudo sk-nft-show
    sudo sk-nft-show --log

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
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

if ! command -v nft >/dev/null 2>&1 && ! command -v iptables >/dev/null 2>&1; then
    die "neither 'nft' nor 'iptables' is installed" 5
fi

# =============================================================================
# 6. Main logic
# =============================================================================

header "Front-end firewall"
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active'; then
    pass "UFW is ACTIVE — it owns the nftables ruleset (manage rules via ufw)"
elif systemctl is-active --quiet firewalld 2>/dev/null; then
    pass "firewalld is ACTIVE — it owns the nftables ruleset (manage rules via firewall-cmd)"
else
    warn "no front-end active (ufw/firewalld) — netfilter is unmanaged or hand-managed"
fi

header "iptables backend mode"
if command -v iptables >/dev/null 2>&1; then
    if iptables --version 2>/dev/null | grep -qi 'nf_tables'; then
        info "iptables is the nft shim (iptables-nft) — rules land in nftables"
    else
        warn "iptables appears to be LEGACY (not nft-backed)"
    fi
else
    info "iptables command not present (pure-nftables host)"
fi

header "Live nftables ruleset"
if command -v nft >/dev/null 2>&1; then
    if nft list ruleset 2>/dev/null | grep -q .; then
        nft list ruleset
    else
        info "ruleset is empty (no nftables rules loaded)"
    fi
else
    warn "nft not installed; showing iptables -S instead"
    iptables -S 2>/dev/null || true
fi

header "Persistence state"
if [[ "$SK_DISTRO_FAMILY" == "debian" ]]; then
    NFT_CONF="/etc/nftables.conf"
    if systemctl is-enabled --quiet netfilter-persistent 2>/dev/null; then
        pass "netfilter-persistent is enabled (/etc/iptables/rules.v4)"
    else
        info "netfilter-persistent not enabled"
    fi
else
    NFT_CONF="/etc/sysconfig/nftables.conf"
fi
if systemctl is-enabled --quiet nftables 2>/dev/null; then
    pass "nftables.service enabled (loads $NFT_CONF at boot)"
else
    info "nftables.service not enabled — live rules will NOT survive reboot"
fi
[[ -f "$NFT_CONF" ]] && info "persistence file present: $NFT_CONF" \
                     || info "no persistence file at $NFT_CONF"

header "IP routing table"
ip route show 2>/dev/null || warn "could not read routing table"
if [[ "$VERBOSE" == "1" ]]; then
    info "policy routing rules:"
    ip rule show 2>/dev/null || true
fi

header "Result"
pass "netfilter inspection complete (read-only)"
exit 0
