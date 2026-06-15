# Telemetry agents: Telegraf and Datadog (alternatives to node_exporter)

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

> `[GROUNDING-GAP: telemetry agents — grounded on official InfluxData/Datadog
> docs; no book grounding]`
>
> node_exporter, Telegraf, and the Datadog agent are **absent from the book
> corpus** this engine is grounded on. The content below is authored from the
> official upstream documentation (InfluxData Telegraf docs and Datadog agent
> docs) and is kept deliberately conservative. Pin and verify the package
> repository, GPG key, and config schema against the vendor's current docs
> before relying on exact behaviour. The recommended default for this engine
> remains the OSS **Prometheus `node_exporter`** path in
> [`prometheus-setup.md`](prometheus-setup.md); Telegraf and Datadog are
> documented here as alternatives.

This file is the deep reference for **whole-host telemetry agents** other than
Prometheus `node_exporter`. It covers two:

- **Telegraf** (InfluxData) — an OSS plugin-driven agent that collects system
  metrics and ships them to InfluxDB, Prometheus, or many other backends.
- **Datadog agent** — a SaaS agent that ships metrics, logs, and traces to the
  Datadog cloud platform.

Both run on **both families** (Debian/Ubuntu and the RHEL family: Fedora,
RHEL, CentOS Stream, Rocky, Alma, Oracle). The agents are portable; only the
package repository and the firewall command differ.

## Table of contents

- [When to use which](#when-to-use-which)
- [Telegraf](#telegraf)
  - [Install Telegraf](#install-telegraf)
  - [telegraf.conf inputs and outputs](#telegrafconf-inputs-and-outputs)
  - [Service management and validation](#telegraf-service-management-and-validation)
- [Datadog agent](#datadog-agent)
  - [Install the Datadog agent](#install-the-datadog-agent)
  - [datadog.yaml and the API key](#datadogyaml-and-the-api-key)
  - [Enabling integrations](#enabling-datadog-integrations)
  - [Privacy and egress: a SaaS agent leaves your network](#privacy-and-egress-a-saas-agent-leaves-your-network)
- [API-key handling](#api-key-handling)

---

## When to use which

| Agent | Model | Ships to | Use when |
|---|---|---|---|
| **node_exporter** (default) | OSS, pull | Your own Prometheus server scrapes it | You run (or want to run) your own Prometheus/Grafana stack; minimal attack surface; metrics only. **This is the engine's recommended default.** |
| **Telegraf** | OSS, push | InfluxDB, Prometheus remote-write, or 200+ outputs | You already run InfluxDB, or you want one agent that pushes a rich plugin set (systemd, SNMP, MySQL, etc.) without writing exporters. Stays inside your network. |
| **Datadog agent** | SaaS, push | Datadog cloud (`*.datadoghq.com` / `.eu` etc.) | Your org has paid for Datadog and wants metrics + logs + APM in one managed platform, and is comfortable shipping operational data to a third party. |

Rule of thumb: **prefer `node_exporter`** unless you have a concrete reason
(an existing InfluxDB → Telegraf; a paid Datadog contract → Datadog). Each
extra agent is another privileged daemon and another scrape/egress surface.

---

## Telegraf

Telegraf is a single static Go binary driven by `/etc/telegraf/telegraf.conf`.
It has **input plugins** (what to collect) and **output plugins** (where to
send it). It runs as the `telegraf` user and reads most system metrics without
root, except where a plugin needs elevated access (e.g. some disk/SMART
inputs).

### Install Telegraf

InfluxData ships signed apt/dnf repositories. Always import the GPG key over
HTTPS and pin the repo; do not pipe a remote script straight into a shell
without reading it.

**Debian/Ubuntu:**

```bash
# Import InfluxData's signing key into a dedicated keyring
curl -fsSL https://repos.influxdata.com/influxdata-archive.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/influxdata-archive.gpg

echo "deb [signed-by=/usr/share/keyrings/influxdata-archive.gpg] \
https://repos.influxdata.com/debian stable main" \
  | sudo tee /etc/apt/sources.list.d/influxdata.list

sudo apt update
sudo apt install -y telegraf
```

**RHEL family** (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle):

```bash
sudo tee /etc/yum.repos.d/influxdata.repo >/dev/null <<'EOF'
[influxdata]
name = InfluxData Repository - Stable
baseurl = https://repos.influxdata.com/stable/$basearch/main
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdata-archive.key
EOF

sudo dnf install -y telegraf      # yum on older RHEL/CentOS
```

The package installs the `telegraf` systemd unit and a default config. It does
**not** open any inbound port for the system inputs below; Telegraf is a *push*
agent. You only open a firewall port if you enable an inbound input (e.g. the
`prometheus_client` output, which exposes `/metrics` on a port).

### telegraf.conf inputs and outputs

Edit `/etc/telegraf/telegraf.conf` (or, preferably, drop fragments in
`/etc/telegraf/telegraf.d/*.conf` so package upgrades don't clobber your
changes). A minimal host-metrics config:

```toml
# /etc/telegraf/telegraf.d/10-system.conf

[agent]
  interval = "10s"
  round_interval = true
  hostname = ""           # empty = use os.Hostname()
  omit_hostname = false

# ---------- INPUTS (what to collect) ----------
[[inputs.cpu]]
  percpu = true
  totalcpu = true
  collect_cpu_time = false
  report_active = false

[[inputs.mem]]

[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "overlay", "squashfs"]

[[inputs.diskio]]

[[inputs.net]]

[[inputs.system]]        # load average, uptime

[[inputs.systemd_units]] # per-unit active/failed state
  unittype = "service"
```

Pick **one** output. Two common ones:

**Push to InfluxDB v2:**

```toml
# /etc/telegraf/telegraf.d/20-output-influxdb.conf
[[outputs.influxdb_v2]]
  urls = ["https://influx.internal:8086"]
  token = "${INFLUX_TOKEN}"   # from /etc/default/telegraf — see API-key handling
  organization = "ops"
  bucket = "hosts"
```

**Expose a Prometheus scrape endpoint** (lets a Prometheus server scrape
Telegraf the same way it scrapes node_exporter — useful as a drop-in richer
exporter):

```toml
# /etc/telegraf/telegraf.d/20-output-prometheus.conf
[[outputs.prometheus_client]]
  listen = "127.0.0.1:9273"   # bind to loopback; firewall to the monitor IP
  metric_version = 2
```

If you use `prometheus_client`, treat the port exactly like node_exporter's
9100: bind to `127.0.0.1` (or firewall-restrict to the monitoring server's IP
only — never `0.0.0.0` open to the world):

```bash
# Debian/Ubuntu
sudo ufw allow from 10.0.0.5 to any port 9273 proto tcp
# RHEL family
sudo firewall-cmd --add-rich-rule='rule family=ipv4 source address=10.0.0.5 \
  port port=9273 protocol=tcp accept' --permanent && sudo firewall-cmd --reload
```

The same **cardinality discipline** from `prometheus-setup.md` applies: do not
tag metrics with high-cardinality values (request IDs, user IDs). Telegraf
tags become Prometheus labels / InfluxDB tag keys and will explode the backend.

### Telegraf service management and validation

```bash
# Validate the config (fails fast on a bad plugin or TOML error)
sudo telegraf --config-directory /etc/telegraf/telegraf.d --test

sudo systemctl enable --now telegraf
sudo systemctl status telegraf --no-pager
journalctl -u telegraf -n 30 --no-pager

# If using prometheus_client, confirm the scrape endpoint:
curl -s localhost:9273/metrics | head -20
```

`--test` runs every input once and prints the metrics to stdout without
sending them anywhere — run it before every config change goes live.

---

## Datadog agent

The Datadog agent is a **SaaS** agent: it ships metrics, logs, and traces to
Datadog's cloud. It needs an **API key** (per-org) and a **site** (region:
`datadoghq.com`, `datadoghq.eu`, `us3.datadoghq.com`, etc.). Unlike
node_exporter and Telegraf-to-InfluxDB, **data leaves your network** — read the
[privacy and egress](#privacy-and-egress-a-saas-agent-leaves-your-network)
section before deploying.

### Install the Datadog agent

Datadog publishes an official one-line install script and signed repositories.
The script reads `DD_API_KEY` and `DD_SITE` from the environment and configures
the repo, key, and `datadog.yaml` in one step.

```bash
# Inspect the script first (do NOT pipe-to-shell blind):
curl -fsSL https://install.datadoghq.com/scripts/install_script_agent7.sh -o /tmp/dd-install.sh
less /tmp/dd-install.sh

# Then run it with your key and site (region) in the environment:
DD_API_KEY="<your-api-key>" DD_SITE="datadoghq.com" \
  DD_APM_INSTRUMENTATION_ENABLED=host bash /tmp/dd-install.sh
```

Prefer the **repository** install if you manage packages with config
management (Ansible/Puppet): add Datadog's apt/dnf repo + GPG key, then
`apt install datadog-agent` / `dnf install datadog-agent`, and template
`datadog.yaml` yourself. This avoids running the vendor script on every host
and keeps the API key out of shell history.

The package installs the `datadog-agent` systemd unit and runs as the
`dd-agent` user.

### datadog.yaml and the API key

Main config is `/etc/datadog-agent/datadog.yaml` (mode `0640`, owned by
`dd-agent`). The minimum:

```yaml
# /etc/datadog-agent/datadog.yaml
api_key: <your-api-key>      # better: keep this OUT of the file — see below
site: datadoghq.com          # MUST match the region your org is on
hostname: ""                 # blank = auto-detect
tags:
  - env:prod
  - team:platform
logs_enabled: false          # turn on only if you intend to ship logs
```

Keep the API key out of the YAML where possible by exporting it via the unit
environment (`DD_API_KEY`) from a `0600` file owned by root, rather than
committing it to a config-management repo in plaintext. See
[API-key handling](#api-key-handling).

```bash
sudo systemctl restart datadog-agent
sudo datadog-agent status        # shows API connectivity + which checks ran
sudo datadog-agent configcheck   # validates enabled integration configs
```

### Enabling Datadog integrations

Integrations ("checks") live under `/etc/datadog-agent/conf.d/<check>.d/`.
Enable one by dropping a `conf.yaml` from the bundled `conf.yaml.example`:

```bash
# Example: enable the system 'disk' and an nginx integration
sudo cp /etc/datadog-agent/conf.d/nginx.d/conf.yaml.example \
        /etc/datadog-agent/conf.d/nginx.d/conf.yaml
sudo $EDITOR /etc/datadog-agent/conf.d/nginx.d/conf.yaml   # set the status URL
sudo systemctl restart datadog-agent
sudo datadog-agent status | sed -n '/nginx/,+5p'
```

The base system metrics (CPU, memory, disk, network, load) are collected by
the always-on `system` check — no extra config needed.

### Privacy and egress: a SaaS agent leaves your network

This is the decision that separates Datadog from the OSS agents. Be explicit
about it with stakeholders before deploying:

- **Data leaves your perimeter.** Metrics, and (if `logs_enabled: true`) raw
  log lines, are sent to Datadog's cloud at `*.<site>` over TLS on 443/10516.
  Logs frequently contain **PII and secrets** — scrub or exclude sensitive
  sources, and treat enabling log collection as a data-governance decision,
  not a config toggle.
- **Outbound egress.** The agent needs outbound 443 (and 10516 for logs) to
  Datadog's IP ranges. In a locked-down environment you allow-list those, or
  route through a proxy (`proxy:` block in `datadog.yaml`). It does **not** need
  inbound ports — do not open any.
- **Region/data-residency.** `site` pins where data is stored
  (`datadoghq.eu` for EU residency, etc.). Choosing the wrong site silently
  sends data to the wrong jurisdiction.
- **Third-party trust.** A privileged agent with an org-wide API key runs on
  every host. Rotate the key if a host is decommissioned or compromised, and
  scope keys per-environment where your plan allows.

If any of these are unacceptable, stay on the OSS `node_exporter` (or Telegraf
→ self-hosted InfluxDB) path, which keep telemetry inside your network.

---

## API-key handling

Both Telegraf (InfluxDB token) and Datadog (API key) need a long-lived secret
on the host. Handle it the way the [`linux-secrets`](../../../02-users-access-and-secrets/linux-secrets/SKILL.md)
skill prescribes — do not hardcode it in a world-readable config or commit it
to a config-management repo in plaintext:

- Store the secret in a **`0600`, root-owned** environment file and inject it
  via the systemd unit, not inline in the agent config:

  ```bash
  # /etc/default/telegraf  (Debian)  or  /etc/sysconfig/telegraf  (RHEL)
  INFLUX_TOKEN=...        # referenced as ${INFLUX_TOKEN} in telegraf.conf
  ```

  ```bash
  sudo chmod 0600 /etc/default/telegraf
  sudo chown root:root /etc/default/telegraf
  ```

  For Datadog, set `DD_API_KEY` via a systemd drop-in
  (`/etc/systemd/system/datadog-agent.service.d/override.conf`) reading an
  `EnvironmentFile=` with mode `0600`.

- **Rotate** the token/key on host decommission or suspected compromise.
- **Never** log the secret. Telegraf's `--test` and `datadog-agent status`
  redact keys, but a verbose curl or a shell-history line will not — clear
  history (`history -c`) after any manual key handling.
- Where your secrets tooling supports it (Vault, SOPS, cloud secret manager),
  template the env file at deploy time rather than storing the plaintext at
  rest. See [`linux-secrets`](../../../02-users-access-and-secrets/linux-secrets/SKILL.md).

---

## See also

- [`prometheus-setup.md`](prometheus-setup.md) — the recommended default OSS
  path (node_exporter), cardinality discipline, systemd hardening.
- [`log-forwarding.md`](log-forwarding.md) — log shipping (Telegraf and
  Datadog can also collect logs; rsyslog/fluent-bit/vector remain the
  vendor-neutral options).
- [`linux-secrets`](../../../02-users-access-and-secrets/linux-secrets/SKILL.md) —
  secure handling of the InfluxDB token / Datadog API key.
