---
name: linux-observability
description: Add metrics, logs, and health endpoints to Ubuntu/Debian servers — Prometheus node_exporter, centralized logging via rsyslog/fluent-bit, standard /health endpoints. Use for any task involving metrics collection or log shipping.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---

# Linux Observability

This skill owns **metrics and log shipping** — turning a server from a
black box you SSH into occasionally to a first-class citizen of a
monitoring stack.

Complements `linux-system-monitoring` (which is local, interactive: `top`,
`htop`, `iostat`) with remote, continuous, aggregated observability
(Prometheus scrape targets, Loki log streams, `/health` endpoints).

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

- Running `top` to see what's eating CPU right now — use
  `linux-system-monitoring`.
- Rotating or grepping local log files — use `linux-log-management`.
- Alerting rules in Prometheus/Grafana — those live in the monitoring
  server's config, not on this server.

---

## Standing rules

1. **Every managed server exposes `node_exporter` on localhost:9100.** UFW
   opens it only to the monitoring server's IP. `sk-node-exporter-install`
   enforces this pattern.
2. **Every web service has a `/health` endpoint** that checks at minimum:
   database reachable, disk not full, required services running. Returns
   200 on healthy, 503 on unhealthy, JSON body with per-check status.
3. **Logs ship off the server.** Local files are for operator grep, not
   long-term storage. `sk-log-forward-setup` configures rsyslog or
   fluent-bit with TLS to the collector.
4. **Metrics have cardinality discipline.** No per-request unique IDs as
   labels. Ever. (Prometheus explodes; Loki doesn't.)
5. **`node_exporter` runs as its own unprivileged user** (`node_exp`) from
   a systemd unit, never as root.
6. **Health endpoints are authenticated if they expose internals.** Public
   `/health` returns 200/503 only; detail is on an internal port.

---

## Typical workflows

### Making a server visible to Prometheus

```bash
sudo sk-node-exporter-install --monitor-ip 10.0.0.5
```

- Creates `node_exp` user.
- Downloads and verifies node_exporter binary.
- Installs systemd unit listening on `127.0.0.1:9100`.
- Opens UFW on 9100 **only from** `--monitor-ip`.
- Verifies metrics are scraped with `curl localhost:9100/metrics`.

### Adding `/health` to a vhost

```bash
sudo sk-health-endpoint --domain example.com --db mysql --disk /var/www
```

Generates an Nginx location block that proxies to a small PHP/Node handler
running the requested checks and returning JSON. Restarts the site.

### Forwarding logs to Loki

```bash
sudo sk-log-forward-setup --collector loki.internal:3100 --tls
```

Installs fluent-bit, sets up systemd service, configures TLS cert, forwards
journald + nginx/apache access + error logs.

---

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-observability
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-node-exporter-install | scripts/sk-node-exporter-install.sh | no | Install Prometheus node_exporter as an unprivileged systemd service, firewall-restrict to a given monitoring IP, verify scrape. |
| sk-health-endpoint | scripts/sk-health-endpoint.sh | no | Create and verify a `/health` endpoint for a vhost: checks db, disk, required services; returns 200/503 + JSON body. |
| sk-log-forward-setup | scripts/sk-log-forward-setup.sh | no | Configure rsyslog or fluent-bit to forward journald and webserver logs to a central collector over TLS. |

---

## See also

- `linux-system-monitoring` — local, interactive health snapshots.
- `linux-log-management` — local log grep, rotation, retention.
- `linux-firewall-ssl` — opening scrape port and TLS certs for shipping.
- `linux-config-management` — Ansible integration for drift on exporter
  config.
