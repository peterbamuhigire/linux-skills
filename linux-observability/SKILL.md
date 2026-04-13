---
name: linux-observability
description: Add metrics, logs, and health endpoints to Ubuntu/Debian servers — Prometheus node_exporter, centralized logging via rsyslog/fluent-bit, standard /health endpoints. Use for any task involving metrics collection or log shipping off the host.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---

# Linux Observability

## Use when

- Adding metrics collection, log shipping, or health endpoints to a server.
- Making a host visible to Prometheus or a central logging pipeline.
- Standardizing `/health` behavior for operational checks.

## Do not use when

- The task is reading local logs only; use `linux-log-management`.
- The task is general performance triage without telemetry design work; use `linux-system-monitoring`.

## Required inputs

- The telemetry layer involved: metrics, logs, or health endpoint.
- The target collector, Prometheus server, or log destination.
- The service or vhost that needs instrumentation.

## Workflow

1. Choose the telemetry layer required by the task.
2. Follow the matching setup or troubleshooting workflow below.
3. Validate the exported metric, forwarded log, or `/health` response from the consumer side.
4. Record any credentials, ports, or retention assumptions needed for operations.

## Quality standards

- Observability changes must be testable from the receiving system, not only from the host.
- Keep health endpoints cheap, deterministic, and safe to expose.
- Prefer standard, maintainable telemetry patterns over bespoke one-offs.

## Anti-patterns

- Declaring a system observable before checking the collector can actually scrape or receive it.
- Shipping logs without understanding destination, transport, or retention.
- Turning `/health` into a heavy application diagnostic endpoint.

## Outputs

- The metrics, logs, or health integration added or diagnosed.
- The validation method used from the consumer side.
- Any remaining operational prerequisites or exposure notes.

## References

- [`references/prometheus-setup.md`](references/prometheus-setup.md)
- [`references/log-forwarding.md`](references/log-forwarding.md)
- [`references/health-endpoint-pattern.md`](references/health-endpoint-pattern.md)

**This skill is self-contained.** Every step below uses standard
Ubuntu/Debian tools and released binaries. The `sk-*` scripts in the
**Optional fast path** section are convenience wrappers — never required.

This skill owns **metrics and log shipping** — turning a server from a
black box you SSH into occasionally into a first-class citizen of a
monitoring stack.

Complements `linux-system-monitoring` (local, interactive: `top`, `htop`,
`iostat`) with remote, continuous, aggregated observability (Prometheus
scrape targets, Loki log streams, standard `/health` endpoints).

Informed by *Linux System Administration for the 2020s* (observability as
mandatory, not optional).

---

## When to use

- Installing Prometheus `node_exporter` on a server.
- Creating a standard `/health` endpoint for a web service.
- Forwarding logs from a server to a central collector (Loki, ELK,
  CloudWatch).
- Auditing which metrics and logs a server is currently emitting.

## When NOT to use

- `top`, `htop`, `iostat` for right-now triage → `linux-system-monitoring`.
- Grepping local log files → `linux-log-management`.
- Prometheus/Grafana *alerting rules* — those live in the monitoring
  server's config, not on the managed host.

---

## Standing rules

1. **Every managed server exposes `node_exporter` on `127.0.0.1:9100`.**
   UFW allows scrape only from the monitoring server's IP — never from
   `0.0.0.0`. Exporter runs as its own unprivileged user.
2. **Every web service has a `/health` endpoint** that checks at minimum:
   database reachable, disk not full, required services running. 200 on
   healthy, 503 on unhealthy, JSON body with per-check status.
3. **Logs ship off the server.** Local files are for operator grep, not
   long-term storage.
4. **Metrics have cardinality discipline.** No per-request unique IDs as
   labels. Ever. Prometheus explodes on high cardinality.
5. **Public vs internal health endpoints are split.** Public `/health`
   returns minimal info (200/503); internal `/health/detail` (behind
   firewall or auth) returns per-check JSON.
6. **TLS on the wire for log shipping.** Always. No plain-text logs
   crossing the network — they contain PII and tokens.

---

## Quick reference — manual commands

### Install node_exporter from GitHub release (canonical method)

```bash
# 1. Download and verify (check releases: https://github.com/prometheus/node_exporter)
VER=1.8.2
cd /tmp
curl -LO https://github.com/prometheus/node_exporter/releases/download/v${VER}/node_exporter-${VER}.linux-amd64.tar.gz
curl -LO https://github.com/prometheus/node_exporter/releases/download/v${VER}/sha256sums.txt
sha256sum -c sha256sums.txt --ignore-missing 2>&1 | grep OK

# 2. Install
tar xzf node_exporter-${VER}.linux-amd64.tar.gz
sudo install -m 0755 node_exporter-${VER}.linux-amd64/node_exporter /usr/local/bin/

# 3. Unprivileged user
sudo useradd --no-create-home --shell /usr/sbin/nologin node_exp

# 4. Systemd unit
sudo tee /etc/systemd/system/node_exporter.service >/dev/null <<'EOF'
[Unit]
Description=Prometheus node exporter
After=network-online.target
Wants=network-online.target

[Service]
User=node_exp
Group=node_exp
ExecStart=/usr/local/bin/node_exporter --web.listen-address=127.0.0.1:9100
Restart=on-failure
RestartSec=3
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=yes
CapabilityBoundingSet=
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
sudo systemctl status node_exporter --no-pager

# 5. UFW — allow only from monitoring host
sudo ufw allow from 10.0.0.5 to any port 9100 proto tcp

# 6. Verify
curl -s localhost:9100/metrics | head -20
```

Full deep-dive (collectors, textfile collector, other exporters,
systemd hardening options, cardinality discipline) — see
[`references/prometheus-setup.md`](references/prometheus-setup.md).

### Log forwarding with rsyslog (TLS)

```bash
sudo apt install rsyslog-gnutls
sudo mkdir -p /etc/rsyslog.d

# Minimal forwarder config (rsyslog.d/90-forward.conf)
sudo tee /etc/rsyslog.d/90-forward.conf >/dev/null <<'EOF'
$DefaultNetstreamDriver gtls
$DefaultNetstreamDriverCAFile /etc/ssl/certs/loghost-ca.crt
$ActionSendStreamDriverMode 1
$ActionSendStreamDriverAuthMode x509/name
$ActionSendStreamDriverPermittedPeer loghost.internal

$ActionQueueType LinkedList
$ActionQueueFileName fwdRule1
$ActionResumeRetryCount -1
$ActionQueueSaveOnShutdown on

*.* @@loghost.internal:6514
EOF

sudo systemctl restart rsyslog
```

Full setup with fluent-bit, vector, promtail, and journald forwarding —
see [`references/log-forwarding.md`](references/log-forwarding.md).

### Minimal `/health` endpoint (Nginx → PHP)

```bash
# A /health.php file in your web root:
sudo tee /var/www/html/health.php >/dev/null <<'PHP'
<?php
header('Content-Type: application/json');
$checks = [];
$ok = true;

// DB reachable
try {
    $pdo = new PDO('mysql:host=127.0.0.1;dbname=app', 'health', getenv('HEALTH_PASS'));
    $pdo->query('SELECT 1');
    $checks['db'] = 'ok';
} catch (Throwable $e) {
    $checks['db'] = 'fail';
    $ok = false;
}

// Disk < 90% on / and /var
foreach (['/', '/var'] as $mount) {
    $pct = 100 - (disk_free_space($mount) / disk_total_space($mount) * 100);
    $checks["disk:$mount"] = $pct < 90 ? 'ok' : 'fail';
    if ($pct >= 90) $ok = false;
}

http_response_code($ok ? 200 : 503);
echo json_encode(['status' => $ok ? 'ok' : 'fail', 'checks' => $checks]);
PHP
```

Full pattern (Nginx-only health via `stub_status`, Node.js variant,
caching, auth for detail endpoint) — see
[`references/health-endpoint-pattern.md`](references/health-endpoint-pattern.md).

---

## Typical workflows

### Workflow: "Make this server visible to Prometheus"

1. Install node_exporter (command sequence above).
2. `sudo ufw allow from <monitor-ip> to any port 9100 proto tcp`.
3. `curl -s localhost:9100/metrics | head -20` — confirm metrics.
4. Add the server as a scrape target on your Prometheus server (outside
   the scope of this skill — that lives on the monitoring host).

### Workflow: "Add /health to an existing vhost"

1. Write the `health.php` (or Node.js equivalent) above.
2. In the Nginx vhost, add:
   ```nginx
   location = /health {
       include fastcgi_params;
       fastcgi_pass unix:/run/php/php8.3-fpm.sock;
       fastcgi_param SCRIPT_FILENAME /var/www/html/health.php;
       access_log off;
   }
   ```
3. `sudo nginx -t && sudo systemctl reload nginx`.
4. Test: `curl -sI https://example.com/health` → 200 or 503.

### Workflow: "Forward logs to a central Loki collector"

1. Install fluent-bit (`apt install fluent-bit` or upstream repo for
   newer versions).
2. Drop `/etc/fluent-bit/fluent-bit.conf` from
   [`references/log-forwarding.md`](references/log-forwarding.md).
3. `sudo systemctl enable --now fluent-bit`.
4. Verify arrival at the Loki server.

---

## Troubleshooting / gotchas

- **`node_exporter` listening on 0.0.0.0 by accident.** The systemd unit
  above pins `127.0.0.1:9100` — verify with `ss -tlnp | grep 9100`. If
  it's bound everywhere, fix the `--web.listen-address` flag and reload.
- **UFW allows the scrape but Prometheus can't reach it.** Check that
  the rule is `from <monitoring-ip>` not `to <monitoring-ip>`. Easy
  direction confusion.
- **High-cardinality metric explodes Prometheus.** Signs: Prometheus OOMs
  after adding a new exporter. Usually a label with request IDs or user
  IDs. Drop the offending metric or relabel it away.
- **`/health` page cached by CDN.** Set `Cache-Control: no-store` in the
  Nginx location. A cached 200 will hide a real 503 from the load
  balancer for minutes.
- **rsyslog forwarding queues on disk fill /var/spool.** Set a max queue
  size on the `$ActionQueue*` config, and monitor `/var/spool/rsyslog`.
- **Fluent-bit does not automatically rotate its own logs.** Configure
  its log target carefully — it's a log shipper that can create logs.

---

## References

- [`references/prometheus-setup.md`](references/prometheus-setup.md) —
  full node_exporter install, other exporters, cardinality discipline,
  systemd hardening.
- [`references/log-forwarding.md`](references/log-forwarding.md) —
  rsyslog/fluent-bit/vector/promtail with TLS forwarding examples.
- [`references/health-endpoint-pattern.md`](references/health-endpoint-pattern.md) —
  full `/health` pattern with PHP and Node.js examples, internal detail
  endpoint, caching strategy.
- Book: *Linux System Administration for the 2020s* — observability is
  mandatory, not optional.
- Man pages: `rsyslogd(8)`, `systemd.service(5)`.

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-observability` installs:

| Task | Fast-path script |
|---|---|
| Install node_exporter as unprivileged systemd service | `sudo sk-node-exporter-install --monitor-ip <ip>` |
| Create/verify a `/health` endpoint for a vhost | `sudo sk-health-endpoint --domain <d> --db mysql` |
| Configure log forwarding over TLS | `sudo sk-log-forward-setup --collector <host>:<port> --tls` |

These are optional wrappers around the manual steps above.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-observability
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-node-exporter-install | scripts/sk-node-exporter-install.sh | no | Install Prometheus node_exporter as unprivileged systemd service, firewall-restrict, verify scrape. |
| sk-health-endpoint | scripts/sk-health-endpoint.sh | no | Create and verify `/health` for a vhost: checks db, disk, required services; 200/503 + JSON. |
| sk-log-forward-setup | scripts/sk-log-forward-setup.sh | no | Configure rsyslog or fluent-bit to forward journald and webserver logs to a central collector over TLS. |
