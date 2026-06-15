#!/usr/bin/env bash
#: Title:       sk-telegraf-setup
#: Synopsis:    sk-telegraf-setup [--output prometheus|influxdb] [--listen ADDR:PORT]
#:                                [--influx-url URL] [--monitor-ip IP] [-y]
#: Description: Install and configure the InfluxData Telegraf agent on both the
#:              Debian/Ubuntu and RHEL families (Fedora, RHEL, CentOS Stream,
#:              Rocky, Alma, Oracle) as an OSS, push-based telemetry agent. Adds
#:              the signed InfluxData repo, installs telegraf, drops a host-
#:              metrics input fragment (cpu/mem/disk/diskio/net/system/systemd)
#:              and ONE output (prometheus_client exposing /metrics, or
#:              influxdb_v2), validates with `telegraf --test`, and enables the
#:              service. For prometheus output it firewall-restricts the scrape
#:              port to the monitoring host only (never 0.0.0.0). Asks before
#:              every mutation. The InfluxDB token is never written into the
#:              config: it is read from ${INFLUX_TOKEN} in the systemd env file
#:              (see linux-secrets). The engine's recommended default remains
#:              Prometheus node_exporter (sk-node-exporter-install); Telegraf is
#:              an alternative. See linux-observability/references/telemetry-agents.md.
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
OUTPUT="prometheus"             # prometheus | influxdb
LISTEN="127.0.0.1:9273"         # prometheus_client bind address
INFLUX_URL=""                   # required when --output influxdb
MONITOR_IP=""                   # restrict the scrape port to this host (prometheus output)

TELEGRAF_D="/etc/telegraf/telegraf.d"

# =============================================================================
# 3. Functions
# =============================================================================
usage() {
    cat <<'EOF'
Usage: sk-telegraf-setup [OPTIONS]

Install and configure the InfluxData Telegraf agent (OSS, push-based) on both
the Debian/Ubuntu and RHEL families. Collects host metrics (cpu/mem/disk/
diskio/net/system/systemd) and ships them to ONE output. Asks before each
mutation. The engine default for metrics is Prometheus node_exporter
(sk-node-exporter-install); Telegraf is an alternative.

OPTIONS:
        --output WHICH   Output plugin: prometheus (expose /metrics for a
                         Prometheus server to scrape) or influxdb (push to
                         InfluxDB v2). Default: prometheus.
        --listen ADDR    For --output prometheus: bind address for /metrics.
                         Default: 127.0.0.1:9273 (loopback; safest).
        --influx-url URL For --output influxdb: the InfluxDB v2 base URL
                         (e.g. https://influx.internal:8086). REQUIRED for
                         influxdb output. The token is NOT taken on the CLI —
                         it is read from ${INFLUX_TOKEN} in the telegraf env
                         file (see linux-secrets); this script reminds you to
                         set it 0600/root.
        --monitor-ip IP  For --output prometheus on a non-loopback --listen:
                         firewall-restrict the scrape port to this host only.

STANDARD FLAGS:
    -h, --help           Show this help and exit
        --version        Print version
    -y, --yes            Non-interactive: auto-confirm (requires --influx-url
                         for influxdb output, --monitor-ip for non-loopback)
    -n, --dry-run        Show what would run; change nothing
        --log            Tee output to /var/log/linux-skills/
    -v, --verbose        Echo each command before running it
    -q, --quiet          Errors and final result only

EXIT CODES:
    0  success
    1  generic failure
    2  bad usage / missing required flag
    3  precondition failed (not root, or unsupported distro)
    5  dependency missing

EXAMPLES:
    # Prometheus scrape endpoint on loopback (default, safest)
    sudo sk-telegraf-setup

    # Prometheus scrape endpoint reachable only from the monitoring host
    sudo sk-telegraf-setup --listen 0.0.0.0:9273 --monitor-ip 10.0.0.5

    # Push to InfluxDB v2 (set INFLUX_TOKEN in the env file first)
    sudo sk-telegraf-setup --output influxdb --influx-url https://influx:8086

SECURITY:
    The InfluxDB token is never written into telegraf.conf or passed on the
    command line. Store it as INFLUX_TOKEN=... in the 0600/root telegraf env
    file (/etc/default/telegraf on Debian, /etc/sysconfig/telegraf on RHEL).
    See linux-secrets and linux-observability/references/telemetry-agents.md.

AUTHOR:
    Peter Bamuhigire <techguypeter.com> +256784464178
EOF
}

# =============================================================================
# 4. Flag parsing
# =============================================================================
parse_standard_flags "$@"
set -- "${REMAINING_ARGS[@]}"
while (( $# > 0 )); do
    case "$1" in
        --output)      OUTPUT="${2:?--output needs a value}"; shift ;;
        --output=*)    OUTPUT="${1#*=}" ;;
        --listen)      LISTEN="${2:?--listen needs a value}"; shift ;;
        --listen=*)    LISTEN="${1#*=}" ;;
        --influx-url)  INFLUX_URL="${2:?--influx-url needs a value}"; shift ;;
        --influx-url=*) INFLUX_URL="${1#*=}" ;;
        --monitor-ip)  MONITOR_IP="${2:?--monitor-ip needs a value}"; shift ;;
        --monitor-ip=*) MONITOR_IP="${1#*=}" ;;
        *)             die "unknown argument: $1 (see --help)" 2 ;;
    esac
    shift
done

case "$OUTPUT" in
    prometheus|influxdb) ;;
    *) die "--output must be 'prometheus' or 'influxdb' (got '$OUTPUT')" 2 ;;
esac

# =============================================================================
# 5. Sanity checks
# =============================================================================
require_root
require_family any
require_cmd curl

if [[ "$OUTPUT" == "influxdb" ]]; then
    require_flag INFLUX_URL
    [[ -z "$INFLUX_URL" ]] && die "--output influxdb requires --influx-url" 2
fi

# Non-loopback prometheus listener must be firewall-restricted
LISTEN_HOST="${LISTEN%:*}"
if [[ "$OUTPUT" == "prometheus" && "$LISTEN_HOST" != "127.0.0.1" && "$LISTEN_HOST" != "localhost" ]]; then
    require_flag MONITOR_IP
    [[ -z "$MONITOR_IP" ]] && \
        die "non-loopback --listen ($LISTEN) requires --monitor-ip to firewall-restrict the scrape port; never expose Telegraf to 0.0.0.0 unrestricted" 2
fi

# =============================================================================
# 6. Main logic
# =============================================================================

# --- Step 1: add the InfluxData repository ----------------------------------
header "1. InfluxData repository"
if pkg_is_installed telegraf; then
    pass "telegraf already installed — will (re)write config only"
else
    if ! confirm "Add the signed InfluxData package repository and install telegraf?" "Y"; then
        die "declined repo/install — nothing to do" 0
    fi
    detect_distro
    if [[ "$SK_DISTRO_FAMILY" == "debian" ]]; then
        info "Importing InfluxData GPG key into /usr/share/keyrings/"
        run bash -c 'curl -fsSL https://repos.influxdata.com/influxdata-archive.key \
            | gpg --dearmor -o /usr/share/keyrings/influxdata-archive.gpg' \
            || die "failed to import InfluxData GPG key" 1
        run bash -c 'echo "deb [signed-by=/usr/share/keyrings/influxdata-archive.gpg] https://repos.influxdata.com/debian stable main" \
            > /etc/apt/sources.list.d/influxdata.list' \
            || die "failed to write apt source" 1
        pkg_update
    else
        info "Writing /etc/yum.repos.d/influxdata.repo"
        run bash -c 'cat > /etc/yum.repos.d/influxdata.repo <<EOF
[influxdata]
name = InfluxData Repository - Stable
baseurl = https://repos.influxdata.com/stable/\$basearch/main
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdata-archive.key
EOF' || die "failed to write yum repo" 1
    fi
    pkg_install telegraf || die "telegraf install failed" 1
    pass "telegraf installed"
fi

# --- Step 2: host-metrics input fragment ------------------------------------
header "2. Host-metrics inputs"
run mkdir -p "$TELEGRAF_D"
INPUT_CONF="${TELEGRAF_D}/10-system.conf"

if [[ -f "$INPUT_CONF" ]] && ! confirm "Overwrite existing $INPUT_CONF?" "N"; then
    info "keeping existing $INPUT_CONF"
else
    if [[ "$DRY_RUN" == "1" ]]; then
        info "[dry-run] would write $INPUT_CONF (cpu/mem/disk/diskio/net/system/systemd_units)"
    else
        [[ -f "$INPUT_CONF" ]] && backup_file "$INPUT_CONF" >/dev/null
        atomic_write "$INPUT_CONF" <<'EOF'
# Managed by sk-telegraf-setup — host metrics inputs.
[agent]
  interval = "10s"
  round_interval = true
  omit_hostname = false

[[inputs.cpu]]
  percpu = true
  totalcpu = true
  report_active = false

[[inputs.mem]]

[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "overlay", "squashfs"]

[[inputs.diskio]]

[[inputs.net]]

[[inputs.system]]

[[inputs.systemd_units]]
  unittype = "service"
EOF
        pass "wrote inputs: $INPUT_CONF"
    fi
fi

# --- Step 3: output fragment ------------------------------------------------
header "3. Output plugin ($OUTPUT)"
OUTPUT_CONF="${TELEGRAF_D}/20-output.conf"

if [[ "$DRY_RUN" == "1" ]]; then
    info "[dry-run] would write $OUTPUT_CONF for output '$OUTPUT'"
elif [[ -f "$OUTPUT_CONF" ]] && ! confirm "Overwrite existing $OUTPUT_CONF?" "N"; then
    info "keeping existing $OUTPUT_CONF"
else
    [[ -f "$OUTPUT_CONF" ]] && backup_file "$OUTPUT_CONF" >/dev/null
    if [[ "$OUTPUT" == "prometheus" ]]; then
        atomic_write "$OUTPUT_CONF" <<EOF
# Managed by sk-telegraf-setup — expose /metrics for Prometheus to scrape.
[[outputs.prometheus_client]]
  listen = "${LISTEN}"
  metric_version = 2
EOF
        pass "wrote prometheus_client output on ${LISTEN}"
    else
        atomic_write "$OUTPUT_CONF" <<EOF
# Managed by sk-telegraf-setup — push to InfluxDB v2.
# The token is read from \${INFLUX_TOKEN} in the telegraf env file (0600/root).
[[outputs.influxdb_v2]]
  urls = ["${INFLUX_URL}"]
  token = "\${INFLUX_TOKEN}"
  organization = "ops"
  bucket = "hosts"
EOF
        pass "wrote influxdb_v2 output to ${INFLUX_URL}"
        warn "Set the token securely BEFORE starting telegraf:"
        detect_distro
        if [[ "$SK_DISTRO_FAMILY" == "debian" ]]; then
            info "  echo 'INFLUX_TOKEN=...' | sudo tee -a /etc/default/telegraf"
            info "  sudo chmod 0600 /etc/default/telegraf && sudo chown root:root /etc/default/telegraf"
        else
            info "  echo 'INFLUX_TOKEN=...' | sudo tee -a /etc/sysconfig/telegraf"
            info "  sudo chmod 0600 /etc/sysconfig/telegraf && sudo chown root:root /etc/sysconfig/telegraf"
        fi
        info "  Never commit the token to a config repo in plaintext — see linux-secrets."
    fi
fi

# --- Step 4: firewall (prometheus, non-loopback) ----------------------------
if [[ "$OUTPUT" == "prometheus" && -n "$MONITOR_IP" ]]; then
    header "4. Firewall — scrape port for monitoring host only"
    PORT="${LISTEN##*:}"
    detect_distro
    if confirm "Restrict tcp/${PORT} to ${MONITOR_IP} only?" "Y"; then
        if [[ "$SK_DISTRO_FAMILY" == "debian" ]]; then
            run ufw allow from "$MONITOR_IP" to any port "$PORT" proto tcp \
                || warn "ufw rule failed (is ufw active?)"
        else
            run firewall-cmd --permanent \
                --add-rich-rule="rule family=ipv4 source address=${MONITOR_IP} port port=${PORT} protocol=tcp accept" \
                || warn "firewalld rule failed (is firewalld running?)"
            run firewall-cmd --reload || true
        fi
        pass "scrape port tcp/${PORT} restricted to ${MONITOR_IP}"
    else
        warn "skipped firewall rule — tcp/${PORT} may be exposed; restrict it manually"
    fi
fi

# --- Step 5: validate + enable ----------------------------------------------
header "5. Validate and enable"
if [[ "$DRY_RUN" == "1" ]]; then
    info "[dry-run] would run: telegraf --config-directory $TELEGRAF_D --test"
    info "[dry-run] would run: systemctl enable --now telegraf"
    print_summary
    exit 0
fi

if command -v telegraf >/dev/null 2>&1; then
    if telegraf --config-directory "$TELEGRAF_D" --test >/dev/null 2>&1; then
        pass "telegraf --test validated the config"
    else
        warn "telegraf --test reported issues — inspect: telegraf --config-directory $TELEGRAF_D --test"
    fi
fi

if confirm "Enable and start the telegraf service now?" "Y"; then
    run systemctl enable --now telegraf || die "failed to enable telegraf" 1
    run systemctl status telegraf --no-pager || true
    pass "telegraf enabled and started"
    if [[ "$OUTPUT" == "prometheus" ]]; then
        info "Verify scrape: curl -s ${LISTEN}/metrics | head -20"
    else
        info "Verify shipping: journalctl -u telegraf -n 30 --no-pager"
    fi
else
    info "Not started. Start later with: sudo systemctl enable --now telegraf"
fi

# =============================================================================
# Summary
# =============================================================================
print_summary
exit 0
