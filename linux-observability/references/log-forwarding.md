# Log Forwarding: Shipping Logs Off the Box

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Local log files are for operator grep during an incident. They are not
long-term storage, they are not searchable across the fleet, and they
vanish the moment the disk fills or the host is re-imaged. Every managed
server must ship its logs — journald, Nginx/Apache, application logs — to
a central collector over TLS. This file covers the sender side: rsyslog,
fluent-bit, vector, promtail, what to pick and how to configure it.

Kemp's *Linux System Administration for the 2020s* puts it bluntly:
monitoring and logging are among the minimum features a system must have
before it is accepted into production. A server with no log shipping is a
black box with a ticking time bomb in the form of `/var/log`.

## Table of contents

- [Why logs must leave the box](#why-logs-must-leave-the-box)
- [Shipper comparison](#shipper-comparison)
- [Pick one: decision matrix](#pick-one-decision-matrix)
- [rsyslog: TLS forwarding with a resilient queue](#rsyslog-tls-forwarding-with-a-resilient-queue)
- [fluent-bit: tailing Nginx and shipping to Loki](#fluent-bit-tailing-nginx-and-shipping-to-loki)
- [promtail: the Loki-native shipper](#promtail-the-loki-native-shipper)
- [journald: ship the systemd journal](#journald-ship-the-systemd-journal)
- [Structured logs on the producer](#structured-logs-on-the-producer)
- [Drop-in config and rotation without restart](#drop-in-config-and-rotation-without-restart)
- [Wire security: TLS, pinning, rate limiting](#wire-security-tls-pinning-rate-limiting)
- [Verifying logs arrive at the collector](#verifying-logs-arrive-at-the-collector)
- [Sources](#sources)

## Why logs must leave the box

Three reasons. **Forensics survive the host** — a competent attacker
truncates `/var/log` first; logs that already left the box are evidence,
logs on the box are not. **Disks fill** — a log loop fills `/var/log` in
hours and when `/var` is full the machine stops working (OpenSSH cannot
log, you get locked out). **Searchability** — `grep` across 200 hosts is
a 45-minute SSH loop; Loki or Elasticsearch makes it sub-second.

Corollary: local retention should be short (7–14 days) because the
central store is authoritative — configure logrotate accordingly.

## Shipper comparison

| Shipper | Lang | RSS at idle | Best at | Weakness |
|---|---|---|---|---|
| **rsyslog** | C | ~3 MB | Forwarding traditional syslog over TLS; is installed on every Ubuntu/Debian already; extreme resilience via disk-backed queues | Config syntax is archaic; weak at parsing structured JSON log files |
| **fluent-bit** | C | ~5 MB | Tailing arbitrary log files, parsing JSON, shipping to Loki/ES/CloudWatch/Datadog; kube-native | Config lives in its own format; one more package to install |
| **vector** | Rust | ~30 MB | Complex transforms via VRL (Vector Remap Language); multi-destination fan-out; observability-as-pipeline | Heavier than fluent-bit; config is verbose |
| **promtail** | Go | ~25 MB | Loki-native, zero-effort journald and file tailing with relabelling that mirrors Prometheus | Loki-only; Grafana Labs is deprecating it in favour of Alloy |
| **Grafana Alloy** | Go | ~40 MB | Modern replacement for promtail + grafana-agent; speaks OTLP, Loki, Prometheus remote-write | New project; more moving parts than you may want on a leaf server |

Rsyslog and fluent-bit are the two shippers this skill actively
supports. Vector is fine but the RSS cost adds up at 200+ hosts.
Promtail works well if your central store is exclusively Loki.

## Pick one: decision matrix

- Syslog-native collector (syslog-ng, rsyslog server, Graylog GELF):
  **rsyslog** — already installed, speaks the protocol natively.
- Loki / Elasticsearch / CloudWatch / Datadog / arbitrary HTTPS:
  **fluent-bit** — low RSS, rich parsers, TLS built in.
- Loki-only with Prometheus-style relabelling: **promtail** (or Alloy).
- Aggressive per-host transforms (PII scrub, fan-out): **vector**.

One shipper per host. Never run rsyslog and fluent-bit on the same file
or you will see duplicates at the collector.

## rsyslog: TLS forwarding with a resilient queue

Install GnuTLS support (the default rsyslog lacks it on minimal Ubuntu):

```bash
sudo apt install -y rsyslog rsyslog-gnutls
```

Place the collector CA at `/etc/rsyslog.d/ca.pem` (`0644 root:root`).
Only distribute client keys if the collector requires mTLS, and generate
a unique cert per host. Write `/etc/rsyslog.d/60-forward.conf`:

```text
global(
    defaultNetstreamDriver="gtls"
    defaultNetstreamDriverCAFile="/etc/rsyslog.d/ca.pem"
)

# Messages spool to disk when the collector is unreachable, surviving
# rsyslog restarts and collector outages.
action(
    type="omfwd"
    target="logs.internal.example.com"
    port="6514"
    protocol="tcp"

    StreamDriver="gtls"
    StreamDriverMode="1"          # TLS required
    StreamDriverAuthMode="x509/name"
    StreamDriverPermittedPeers="logs.internal.example.com"
    template="RSYSLOG_SyslogProtocol23Format"

    queue.type="LinkedList"
    queue.filename="fwd_central"
    queue.spoolDirectory="/var/spool/rsyslog"
    queue.maxDiskSpace="1g"
    queue.saveOnShutdown="on"
    queue.size="100000"
    queue.dequeueBatchSize="1000"

    action.resumeRetryCount="-1"   # retry forever
    action.resumeInterval="30"
)
```

Field notes:

- `StreamDriverMode="1"` — `1` = TLS required; `0` would be plain TCP,
  never acceptable (in 2026 "untrusted network" includes your own VPC).
- `StreamDriverAuthMode="x509/name"` with `StreamDriverPermittedPeers` —
  certificate pinning against the collector's CN/SAN; a stolen cert
  from a different host under the same CA cannot impersonate it.
- `queue.type="LinkedList"` + `queue.filename` — in-memory ring with
  on-disk overflow. Without this, a network blip drops every in-flight
  message.
- `action.resumeRetryCount="-1"` — retry forever. The default (`0`)
  suspends the action after one failure and drops every subsequent
  message until rsyslog restarts.
- `queue.saveOnShutdown="on"` — queue items written to disk on stop,
  replayed on next start.

Create the spool directory and validate before reloading:

```bash
sudo install -d -o syslog -g adm -m 0750 /var/spool/rsyslog
sudo rsyslogd -N1
sudo systemctl restart rsyslog
```

## fluent-bit: tailing Nginx and shipping to Loki

Install from the upstream apt repo (the Ubuntu-bundled package lags):

```bash
curl -fsSL https://packages.fluentbit.io/fluentbit.key | \
  sudo gpg --dearmor -o /usr/share/keyrings/fluentbit.gpg
echo "deb [signed-by=/usr/share/keyrings/fluentbit.gpg] https://packages.fluentbit.io/ubuntu/$(lsb_release -cs) $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/fluent-bit.list
sudo apt update && sudo apt install -y fluent-bit
```

Edit `/etc/fluent-bit/fluent-bit.conf`:

```ini
[SERVICE]
    Flush         5
    Log_Level     info
    Parsers_File  parsers.conf
    HTTP_Server   On
    HTTP_Listen   127.0.0.1
    HTTP_Port     2020

# Nginx access log (JSON format — see "Structured logs" below)
[INPUT]
    Name              tail
    Path              /var/log/nginx/access.log
    Parser            nginx
    Tag               nginx.access
    DB                /var/lib/fluent-bit/nginx-access.db
    Refresh_Interval  5
    Mem_Buf_Limit     10MB
    Skip_Long_Lines   On

# Nginx error log
[INPUT]
    Name              tail
    Path              /var/log/nginx/error.log
    Tag               nginx.error
    DB                /var/lib/fluent-bit/nginx-error.db
    Mem_Buf_Limit     10MB

# Apache access log (if present)
[INPUT]
    Name              tail
    Path              /var/log/apache2/access.log
    Parser            apache2
    Tag               apache.access
    DB                /var/lib/fluent-bit/apache-access.db
    Mem_Buf_Limit     10MB

# Stamp every record with the hostname
[FILTER]
    Name          record_modifier
    Match         *
    Record        host ${HOSTNAME}

# Output: Loki over HTTPS, retry forever
[OUTPUT]
    Name              loki
    Match             *
    Host              logs.internal.example.com
    Port              3100
    Tls               On
    Tls.verify        On
    Tls.ca_file       /etc/fluent-bit/ca.pem
    Labels            job=fluent-bit, host=$host, tag=$TAG
    Label_keys        $host,$TAG
    Line_Format       json
    Retry_Limit       False
```

Key points:

- Per-input `DB` files make tailing resumable across restarts; without
  them fluent-bit re-reads whole files and duplicates on restart.
- `Retry_Limit False` — retry forever. Silent drop is worse than block.
- `Labels` — Loki labels. Keep them bounded (`host`, `tag`, `job`).
  Never label by request ID, user ID, or URL path. Loki penalises
  high-cardinality labels; it does not explode the way Prometheus does
  but it will get slow and expensive.
- Set `storage.type filesystem` on inputs if you want disk-backed
  buffering equivalent to rsyslog's disk queue.

Validate and enable:

```bash
sudo mkdir -p /var/lib/fluent-bit
sudo /opt/fluent-bit/bin/fluent-bit --dry-run --config /etc/fluent-bit/fluent-bit.conf
sudo systemctl enable --now fluent-bit
sudo systemctl status fluent-bit
curl -sS http://127.0.0.1:2020/api/v1/metrics | head -40
```

The built-in HTTP server at `127.0.0.1:2020` exposes fluent-bit's own
metrics — scrape them with Prometheus via the `fluentbit_input_*` and
`fluentbit_output_*` families to know whether shipping is keeping up.

## promtail: the Loki-native shipper

When the only destination is Loki and you want Prometheus-style
relabelling, promtail is the simplest option. Install from Grafana's apt
repo or the upstream tarball. `/etc/promtail/config.yml`:

```yaml
server:
  http_listen_address: 127.0.0.1
  http_listen_port: 9080
positions:
  filename: /var/lib/promtail/positions.yaml
clients:
  - url: https://logs.internal.example.com:3100/loki/api/v1/push
    tls_config:
      ca_file: /etc/promtail/ca.pem
      server_name: logs.internal.example.com
    backoff_config: { min_period: 500ms, max_period: 5m, max_retries: 0 }
scrape_configs:
  - job_name: journal
    journal:
      max_age: 12h
      labels: { job: systemd-journal, host: ${HOSTNAME} }
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'
  - job_name: nginx
    static_configs:
      - targets: [localhost]
        labels:
          job: nginx
          host: ${HOSTNAME}
          __path__: /var/log/nginx/*.log
```

Grafana Labs has put promtail into maintenance; Alloy is the
successor. Evaluate Alloy for new installs; promtail is still
supported for existing fleets.

## journald: ship the systemd journal

Two strategies; never both at once (you will double-ship).

**A. fluent-bit reads journald directly.** Add a `systemd` input:

```ini
[INPUT]
    Name             systemd
    Tag              journal.*
    Systemd_Filter   _SYSTEMD_UNIT=sshd.service
    Systemd_Filter   _SYSTEMD_UNIT=nginx.service
    Systemd_Filter   _SYSTEMD_UNIT=php8.3-fpm.service
    Read_From_Tail   On
    DB               /var/lib/fluent-bit/journal.db
```

Drop the filters to ship everything. `Read_From_Tail On` means the
journal backlog is not re-shipped on first start.

**B. rsyslog reads the journal via `imjournal`.** Loaded by default on
Ubuntu (`module(load="imjournal" StateFile="imjournal.state")` in
`/etc/rsyslog.conf`). With this active, everything in the journal flows
through the rsyslog forwarder above — zero extra effort when rsyslog is
already the chosen shipper.

## Structured logs on the producer

Shipping is easier and queries are faster when the log is already JSON
on disk.

**Nginx access log — JSON.** `/etc/nginx/conf.d/log-json.conf`:

```nginx
log_format json_combined escape=json
  '{"time":"$time_iso8601","host":"$host","remote_addr":"$remote_addr",'
  '"request_method":"$request_method","request_uri":"$request_uri",'
  '"status":$status,"body_bytes_sent":$body_bytes_sent,'
  '"request_time":$request_time,"upstream_response_time":"$upstream_response_time",'
  '"http_referer":"$http_referer","http_user_agent":"$http_user_agent",'
  '"request_id":"$request_id"}';
access_log /var/log/nginx/access.log json_combined;
```

`escape=json` escapes quotes and control characters so the JSON stays
valid even with malicious user agents.

**Nginx error log — no JSON.** Nginx does not support JSON for the
error log. Keep the default format and parse on the shipper; fluent-bit
has a built-in `nginx` parser for the access format and you add a
`regex` parser for the error format:

```ini
[PARSER]
    Name        nginx_error
    Format      regex
    Regex       ^(?<time>\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) \[(?<level>\w+)\] (?<pid>\d+)#(?<tid>\d+): (?<message>.*)$
    Time_Key    time
    Time_Format %Y/%m/%d %H:%M:%S
```

**Apache access log — JSON.** `/etc/apache2/conf-available/log-json.conf`:

```apache
LogFormat "{\"time\":\"%{%Y-%m-%dT%H:%M:%S%z}t\",\"host\":\"%V\",\"remote_addr\":\"%a\",\"request_method\":\"%m\",\"request_uri\":\"%U%q\",\"status\":%>s,\"bytes_sent\":%B,\"request_time_us\":%D,\"referer\":\"%{Referer}i\",\"user_agent\":\"%{User-Agent}i\"}" json_combined
CustomLog ${APACHE_LOG_DIR}/access.log json_combined
```

Enable with `sudo a2enconf log-json && sudo systemctl reload apache2`.

**PHP, Python, Node.js apps.** Log to stdout as one JSON object per
line; systemd captures via the journal and the journal shipper handles
the rest. Libraries: monolog `JsonFormatter` (PHP), `python-json-logger`
(Python), `pino` (Node.js).

## Drop-in config and rotation without restart

Both shippers handle rotation without restart when configured
correctly. rsyslog's `imfile` uses inotify and follows files through
rotation automatically. fluent-bit's `tail` input with
`Refresh_Interval 5` catches rotations via glob paths every 5 s;
ensure logrotate uses `create` (the default) or `copytruncate`, never
`nocreate`.

Nginx logrotate fragment that works with both shippers:

```text
/var/log/nginx/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        [ -f /run/nginx.pid ] && kill -USR1 $(cat /run/nginx.pid) || true
    endscript
}
```

The `postrotate` USR1 signal makes Nginx re-open its log files; the
shipper reads the rotated file until EOF, then picks up the new one.

## Wire security: TLS, pinning, rate limiting

Non-negotiable rules:

1. **TLS always.** Plain TCP syslog (514) or plain HTTP Loki push is
   forbidden, even inside a "trusted" VPC.
2. **Verify the server certificate.** fluent-bit `Tls.verify On`;
   rsyslog `StreamDriverMode=1` + `StreamDriverAuthMode=x509/name`.
3. **Pin the server name.** rsyslog `StreamDriverPermittedPeers`;
   fluent-bit `Tls.verify_hostname On` (default with `Tls.verify On`).
4. **Trust the CA, not the leaf cert** — rotations break otherwise.
5. **mTLS when the collector is off-net.** Per-host client cert;
   revoke on decommission.
6. **Rate-limit the sender** so a log loop cannot DoS the collector.
   rsyslog: `action.execOnlyEveryNthTime` / `ratelimit`. fluent-bit:
   `throttle` filter. Sane ceiling: 1000 msg/s per host.
7. **Drop secrets before shipping.** Access tokens in query strings,
   `Authorization` headers, API keys — fluent-bit `modify`/`lua`,
   rsyslog property replacer.

## Verifying logs arrive at the collector

"The service started" is not proof that logs are flowing. Verify
end-to-end with a canary.

On the sender:

```bash
logger -t log-forward-check "canary $(date +%s) host=$(hostname)"
curl -sS http://127.0.0.1:2020/api/v1/metrics | grep -E 'input|output'
sudo journalctl -u fluent-bit -n 20 --no-pager
sudo journalctl -u rsyslog    -n 20 --no-pager
```

On the collector (Loki example):

```bash
curl -G -s "https://logs.internal.example.com:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={host="web-01"} |= "log-forward-check"' \
  --data-urlencode "start=$(date -d '5 min ago' +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" | jq .
```

For Graylog or Elasticsearch use the HTTP search endpoint with the
same canary token. Log shipping is "known good" only after a fresh
canary round-trips.

Automate it: a systemd timer runs `logger -t canary "$(date)"` every 5
minutes and a blackbox check on the collector alerts if the canary
stops arriving. This catches silent shipper failures that the
shipper's own status would not flag.

## Sources

- Brian Kemp, *Linux System Administration for the 2020s: The Modern
  Sysadmin Leaving Behind the Culture of Build and Maintain* —
  Chapter 8 "Logging" (Rsyslog, Fluentd, central logging systems,
  sending logs to a central service, monitoring + logging as minimum
  production features).
- rsyslog project — `omfwd` module, GnuTLS driver, reliable forwarding,
  queue parameters (<https://www.rsyslog.com/doc/>).
- Fluent Bit documentation — `tail`, `systemd`, `loki`, `record_modifier`
  (<https://docs.fluentbit.io/>).
- Grafana Labs — promtail configuration, Loki label cardinality
  guidance; Alloy migration notes.
- Nginx, Apache `mod_log_config` — structured (JSON) log format
  configuration.
- systemd.journal(8), logrotate(8).
