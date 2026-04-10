# Prometheus node_exporter on Ubuntu/Debian

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Install Prometheus `node_exporter` on every managed Ubuntu/Debian server as
an unprivileged systemd service, firewall-lock the scrape port to the
monitoring server's IP only, and verify the scrape before walking away. The
goal is not "a server emits metrics"; the goal is "a server is a
first-class citizen of the monitoring stack, with the smallest possible
attack surface." This file covers only the server-side (exporter) install.
Prometheus server, Alertmanager, and Grafana live on a separate monitoring
host and are out of scope here.

Observability is not optional. *Linux System Administration for the 2020s*
(Kemp) lists monitoring alongside security as the minimum bar a host must
clear before it is accepted into production. If you cannot scrape it, you
cannot alert on it; if you cannot alert on it, it will fail silently.

## Table of contents

- [Prometheus stack overview](#prometheus-stack-overview)
- [node_exporter install steps](#node_exporter-install-steps)
- [Create the unprivileged user](#create-the-unprivileged-user)
- [systemd unit with hardening](#systemd-unit-with-hardening)
- [UFW rule: scrape only from the monitoring server](#ufw-rule-scrape-only-from-the-monitoring-server)
- [Testing the scrape locally](#testing-the-scrape-locally)
- [Enabled vs disabled collectors](#enabled-vs-disabled-collectors)
- [Textfile collector for custom metrics](#textfile-collector-for-custom-metrics)
- [Cardinality discipline](#cardinality-discipline)
- [Other exporters on the same server](#other-exporters-on-the-same-server)
- [Upgrading node_exporter](#upgrading-node_exporter)
- [Troubleshooting](#troubleshooting)
- [Sources](#sources)

## Prometheus stack overview

A working Prometheus deployment has four moving parts. Only the first lives
on the server being monitored.

| Component | Role | Lives on |
|---|---|---|
| Exporter (e.g. node_exporter) | Exposes metrics over HTTP on `/metrics` | Every managed server |
| Prometheus server | Pulls (scrapes) metrics on a schedule, stores them as a time series | Monitoring host |
| Alertmanager | Receives alerts from Prometheus, groups/routes them to email, Slack, PagerDuty | Monitoring host |
| Grafana | Queries Prometheus (PromQL) and draws dashboards | Monitoring host |

Prometheus uses a pull model: the monitoring server reaches out to each
exporter and fetches `/metrics`. That means every server needs an HTTP
endpoint reachable from the monitoring server — and *only* from the
monitoring server.

## node_exporter install steps

Install as a plain binary from the upstream GitHub release. Do not use the
distro `prometheus-node-exporter` package on long-lived boxes — it lags
upstream by 12 to 24 months and bundles collectors you do not want.

```bash
# 1. Pick a version (check https://github.com/prometheus/node_exporter/releases)
NE_VERSION=1.8.2
ARCH=linux-amd64

# 2. Download the tarball and its checksum
cd /tmp
wget "https://github.com/prometheus/node_exporter/releases/download/v${NE_VERSION}/node_exporter-${NE_VERSION}.${ARCH}.tar.gz"
wget "https://github.com/prometheus/node_exporter/releases/download/v${NE_VERSION}/sha256sums.txt"

# 3. Verify the checksum BEFORE extracting
grep "node_exporter-${NE_VERSION}.${ARCH}.tar.gz" sha256sums.txt | sha256sum -c -
# Must print: node_exporter-1.8.2.linux-amd64.tar.gz: OK

# 4. Extract and install the binary
tar -xzf "node_exporter-${NE_VERSION}.${ARCH}.tar.gz"
sudo install -o root -g root -m 0755 \
  "node_exporter-${NE_VERSION}.${ARCH}/node_exporter" \
  /usr/local/bin/node_exporter

# 5. Confirm the binary is installed and version is correct
/usr/local/bin/node_exporter --version
```

If you run a fleet with signature verification, fetch the release's
cosign/gpg signature from the same GitHub release page and verify with
`cosign verify-blob` or `gpg --verify` before step 4. Treat an unverified
binary as compromised.

## Create the unprivileged user

`node_exporter` must never run as root. It does not need a shell, a home
directory, or a password.

```bash
sudo useradd \
  --system \
  --no-create-home \
  --shell /usr/sbin/nologin \
  node_exp
```

Flags explained:

- `--system` — uses a UID below 1000; excluded from interactive login
  listings; no password aging.
- `--no-create-home` — no `/home/node_exp`; nothing to back up, nothing to
  hide a payload in.
- `--shell /usr/sbin/nologin` — if anyone ever tries `su - node_exp`, it
  refuses.

Verify:

```bash
id node_exp
# uid=998(node_exp) gid=998(node_exp) groups=998(node_exp)
getent passwd node_exp
# node_exp:x:998:998::/home/node_exp:/usr/sbin/nologin
```

## systemd unit with hardening

Write the unit to `/etc/systemd/system/node_exporter.service`.

```ini
[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=node_exp
Group=node_exp
ExecStart=/usr/local/bin/node_exporter \
  --web.listen-address=127.0.0.1:9100 \
  --collector.textfile.directory=/var/lib/node_exporter/textfile \
  --collector.systemd \
  --collector.processes \
  --no-collector.wifi \
  --no-collector.nfs \
  --no-collector.nfsd \
  --no-collector.mdadm \
  --no-collector.zfs \
  --no-collector.infiniband
Restart=on-failure
RestartSec=5s

# --- Hardening (systemd sandboxing) ---
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
CapabilityBoundingSet=
AmbientCapabilities=
ReadWritePaths=/var/lib/node_exporter/textfile

[Install]
WantedBy=multi-user.target
```

Key decisions annotated:

- `--web.listen-address=127.0.0.1:9100` — bind to loopback only. The
  exporter is never reachable directly from the network. UFW DNATs or you
  put an `iptables` rule to forward from the scrape IP (below). Most teams
  instead bind to the VPC IP and rely on UFW — both are fine; loopback is
  the paranoid default.
- `ProtectSystem=strict` — the entire filesystem is read-only to the
  process except paths listed in `ReadWritePaths=`.
- `ProtectHome=yes` — `/home`, `/root`, `/run/user` are invisible.
- `CapabilityBoundingSet=` (empty) — drops every Linux capability,
  including `CAP_NET_BIND_SERVICE`. node_exporter binds to 9100 (> 1024),
  so it does not need any capability at all.
- `SystemCallFilter=@system-service` then `~@privileged @resources` —
  whitelist common service syscalls, then blacklist privileged/resource
  syscalls. A 0-day in node_exporter cannot, for example, call
  `setuid(0)`.
- `MemoryDenyWriteExecute=yes` — no RWX pages; blocks classic shellcode
  injection.
- `ReadWritePaths=/var/lib/node_exporter/textfile` — exporter can only
  write to its textfile collector directory.

Create the textfile directory and enable the unit:

```bash
sudo mkdir -p /var/lib/node_exporter/textfile
sudo chown node_exp:node_exp /var/lib/node_exporter/textfile
sudo chmod 0755 /var/lib/node_exporter/textfile

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter.service
sudo systemctl status node_exporter.service
```

Confirm all the hardening stuck:

```bash
sudo systemd-analyze security node_exporter.service
# Look for overall exposure level "OK" and an exposure score below ~2.5.
```

## UFW rule: scrape only from the monitoring server

The exporter listens on 127.0.0.1:9100, which already means the network
cannot reach it. If you chose to bind to an internal IP instead (e.g.
`10.0.0.42:9100`), you MUST firewall it. Never open 9100 to `0.0.0.0/0`
under any circumstances.

Scenario A — loopback bind + SSH tunnel from the monitoring server (no UFW
rule needed):

```bash
# On the monitoring host, scrape over an SSH tunnel:
ssh -L 9100:127.0.0.1:9100 alice@web-01
curl http://127.0.0.1:9100/metrics
```

Scenario B — bind to internal IP, UFW whitelist the monitoring server:

```bash
# Replace 10.0.0.5 with your actual monitoring host IP.
sudo ufw allow from 10.0.0.5 to any port 9100 proto tcp \
  comment 'prometheus scrape from monitoring host'

# Explicitly deny everyone else (belt-and-braces; UFW default-deny should
# already cover this, but an explicit deny line is self-documenting).
sudo ufw deny 9100/tcp comment 'node_exporter denied by default'

sudo ufw reload
sudo ufw status verbose | grep 9100
```

If you have more than one monitoring host (HA Prometheus pair), repeat the
allow rule per IP. Do not use a CIDR wider than `/32` unless the entire
CIDR belongs to monitoring infrastructure.

## Testing the scrape locally

Before you declare the server "on monitoring," scrape it yourself:

```bash
# From the server itself
curl -sS http://127.0.0.1:9100/metrics | head -30
curl -sS http://127.0.0.1:9100/metrics | grep -c '^node_'
# Should print a number in the high hundreds (usually 800–1500).

# From the monitoring server (assuming scenario B)
curl -sS http://10.0.0.42:9100/metrics | grep node_load1
# node_load1 0.21
```

From the Prometheus UI (`/targets`), the target must show `UP` and `Last
Scrape` within the scrape interval. If it shows `DOWN`, go back to UFW.

## Enabled vs disabled collectors

node_exporter ships with ~50 collectors. Most are enabled by default. On a
plain Ubuntu web/app server, disable collectors for subsystems you do not
run — every enabled collector costs CPU, file descriptors, and scrape
duration.

Sensible defaults by use case:

| Server role | Enable extras | Disable |
|---|---|---|
| Web (Nginx + PHP-FPM) | `systemd`, `processes` | `wifi`, `nfs`, `nfsd`, `mdadm`, `zfs`, `infiniband`, `ipvs` |
| DB (MySQL/Postgres) | `systemd`, `processes`, `filefd` | `wifi`, `nfs`, `nfsd`, `infiniband` |
| NFS server | `nfsd`, `mountstats` | `wifi`, `infiniband` |
| Mail (Postfix) | `systemd`, `processes` | `wifi`, `nfs`, `nfsd`, `mdadm`, `zfs` |

Pass `--collector.<name>` to enable, `--no-collector.<name>` to disable.
The unit file above shows the pattern.

List what is actually active on a running instance:

```bash
curl -sS http://127.0.0.1:9100/metrics | \
  grep -oP 'node_scrape_collector_success\{collector="\K[^"]+' | sort -u
```

## Textfile collector for custom metrics

The textfile collector exposes any `.prom` file dropped into
`/var/lib/node_exporter/textfile` as metrics. This is how you publish
custom, server-local facts that no ordinary collector knows about: backup
age, last Ansible run, certificate expiry, queue depth.

Format (Prometheus exposition format, one metric per block):

```text
# HELP backup_last_success_timestamp Unix time of last successful backup.
# TYPE backup_last_success_timestamp gauge
backup_last_success_timestamp 1728489600
```

Write the file atomically from whatever job produces the fact (cron, a
backup hook, a systemd timer). Atomic rename avoids the scraper reading a
half-written file:

```bash
TMP=$(mktemp --tmpdir=/var/lib/node_exporter/textfile backup.XXXXXX.prom)
printf '# HELP backup_last_success_timestamp ...\n' > "$TMP"
printf '# TYPE backup_last_success_timestamp gauge\n' >> "$TMP"
printf 'backup_last_success_timestamp %s\n' "$(date +%s)" >> "$TMP"
mv "$TMP" /var/lib/node_exporter/textfile/backup.prom
```

Permissions: the file must be readable by `node_exp`. Keep writes owned by
`root:node_exp` mode `0644`.

## Cardinality discipline

This is the single most important rule for running a Prometheus stack, and
it is broken more often than any other. **Never put a high-cardinality
value in a label.**

Forbidden label values:

- Request IDs, trace IDs, session IDs.
- User IDs, email addresses, API keys.
- URLs with path parameters (`/orders/483912`).
- Timestamps.
- Free-form error messages.

Each unique combination of labels is a new time series. A single metric
with a `user_id` label and 100k users becomes 100k series per scrape.
Multiply by 15s scrape interval and a week of retention and the database
explodes. Prometheus will refuse scrapes and alerts will stop firing.

Allowed label values: bounded, stable enums. Examples: `method=GET|POST`,
`status=2xx|3xx|4xx|5xx`, `env=prod|stage`, `instance=web-01`.

High-cardinality context (user IDs, request IDs, trace IDs) belongs in
logs and traces, not metrics. Loki and Tempo handle it; Prometheus does
not.

## Other exporters on the same server

Install additional exporters the same way: binary under `/usr/local/bin`,
unprivileged system user, systemd unit with the same hardening block, UFW
whitelist for the monitoring server IP. Ports by convention:

| Exporter | Port | Purpose | Notes |
|---|---|---|---|
| node_exporter | 9100 | Host CPU, memory, disk, network | The one every server runs |
| mysqld_exporter | 9104 | MySQL/MariaDB stats | Needs a `mysql` user with `PROCESS, REPLICATION CLIENT, SELECT` |
| postgres_exporter | 9187 | PostgreSQL stats | Needs a `monitoring` role |
| nginx-exporter | 9113 | Nginx stub_status | Requires `stub_status on;` in an internal location |
| apache_exporter | 9117 | Apache mod_status | Requires `ExtendedStatus On` and an internal `/server-status` |
| blackbox_exporter | 9115 | External probes (HTTP, ICMP, TCP, DNS) | Runs on the monitoring host, not on every server |
| process-exporter | 9256 | Per-process CPU, memory, FD counts | Useful when one daemon's health matters more than aggregate host load |
| php-fpm_exporter | 9253 | PHP-FPM pool stats | Reads `pm.status_path` |
| redis_exporter | 9121 | Redis stats | One exporter per Redis instance |

`blackbox_exporter` is the only one that does not run on each server — it
probes from the monitoring host outward. Use it for `/health` checks (see
`health-endpoint-pattern.md`), SSL certificate expiry, and
DNS resolution.

Each exporter gets its own unprivileged user (`mysqld_exp`, `pg_exp`,
`nginx_exp`, ...). Do not share the `node_exp` account.

## Upgrading node_exporter

```bash
# Fetch new release, verify, stop, swap, start.
NE_VERSION=1.9.0
cd /tmp
wget "https://github.com/prometheus/node_exporter/releases/download/v${NE_VERSION}/node_exporter-${NE_VERSION}.linux-amd64.tar.gz"
wget "https://github.com/prometheus/node_exporter/releases/download/v${NE_VERSION}/sha256sums.txt"
grep "node_exporter-${NE_VERSION}.linux-amd64.tar.gz" sha256sums.txt | sha256sum -c -

tar -xzf "node_exporter-${NE_VERSION}.linux-amd64.tar.gz"
sudo systemctl stop node_exporter.service
sudo install -o root -g root -m 0755 \
  "node_exporter-${NE_VERSION}.linux-amd64/node_exporter" \
  /usr/local/bin/node_exporter
sudo systemctl start node_exporter.service
/usr/local/bin/node_exporter --version
```

Upgrades are backward compatible within a major version. Read the
release notes before crossing a major (collector names occasionally
change).

## Troubleshooting

| Symptom | Check |
|---|---|
| Target shows `DOWN` in Prometheus | `sudo systemctl status node_exporter`; `sudo ss -ltnp | grep 9100`; `sudo ufw status | grep 9100` |
| `Permission denied` on textfile | `ls -ld /var/lib/node_exporter/textfile`; must be `node_exp`-writable |
| High scrape duration (> 2s) | Disable unused collectors; check `node_scrape_collector_duration_seconds` |
| Metric missing after upgrade | `curl -s 127.0.0.1:9100/metrics | grep <name>`; collector may have been renamed |
| `MemoryDenyWriteExecute` blocks exporter | Only relevant on exotic archs; drop this one line if the service refuses to start and you have verified it is the cause |
| UFW rule ignored | `sudo ufw status numbered`; `deny 9100` must come AFTER the allow-from line |

Service did not start at all:

```bash
sudo journalctl -u node_exporter.service -n 50 --no-pager
sudo systemd-analyze verify /etc/systemd/system/node_exporter.service
```

## Sources

- Brian Kemp, *Linux System Administration for the 2020s: The Modern
  Sysadmin Leaving Behind the Culture of Build and Maintain* — Chapter
  "Monitoring" (Prometheus, exporters, Alertmanager, Grafana stack);
  Chapter 8 "Logging."
- Prometheus project — `node_exporter` README and release notes
  (<https://github.com/prometheus/node_exporter>).
- Prometheus documentation — "Writing Exporters" and "Naming best
  practices" (cardinality discipline).
- systemd.exec(5), systemd.service(5) — sandboxing directives reference.
- `systemd-analyze security` — exposure scoring for service hardening.
