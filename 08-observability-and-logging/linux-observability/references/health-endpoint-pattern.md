# The `/health` Endpoint Pattern

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Every web service on a managed server exposes a `/health` endpoint. It is
the contract with load balancers, uptime monitors, self-healing automation,
and Prometheus blackbox probes. A web service without `/health` is a black
box — automation must SSH in and run `systemctl status`, and by then you
already have an incident. This file specifies the contract, the checks to
include, how to split public vs internal, and working Nginx + PHP code.

## Table of contents

- [Why `/health` matters](#why-health-matters)
- [The contract](#the-contract)
- [Checks to include](#checks-to-include)
- [Public vs internal endpoints](#public-vs-internal-endpoints)
- [Nginx location block](#nginx-location-block)
- [PHP reference implementation](#php-reference-implementation)
- [Nginx-only health: trade-offs](#nginx-only-health-trade-offs)
- [Metrics vs health: different things](#metrics-vs-health-different-things)
- [Frequency, timeouts, and caching](#frequency-timeouts-and-caching)
- [Integration with blackbox_exporter](#integration-with-blackbox_exporter)
- [Sources](#sources)

## Why `/health` matters

Three automated audiences consume `/health`. **Load balancers** (HAProxy,
Nginx upstream health, AWS ALB, Kubernetes probes) pull a backend out of
rotation the instant it stops returning 200 — without `/health` they fall
back to "is the TCP port open?", which says nothing about whether PHP is
wedged, the DB is down, or the disk is full. **Uptime monitors**
(UptimeRobot, Pingdom, `blackbox_exporter`) probe every 30–60 s and alert
on transitions. **Self-healing automation** — "three consecutive 503s,
restart php-fpm; still 503, page on-call" — only works when `/health`
tells the truth.

## The contract

Memorise these rules and enforce them in code review.

- **Path.** `/health` (public), `/health/detail` (internal). Not
  `/healthz`, `/status`, `/ping` — pick one fleet-wide.
- **Method.** `GET` only.
- **Auth.** Public `/health` unauthenticated. `/health/detail`
  authenticated OR firewalled.
- **Success.** `200 OK` when every critical check passes.
- **Failure.** `503 Service Unavailable` when any critical check
  fails. Not 500, not 404. `503` means "up enough to answer, not
  well enough to serve traffic."
- **Content-Type.** `application/json`.
- **Body.** `{status, timestamp, checks}`. Top-level `status` is
  `ok`, `degraded`, or `down`.
- **Latency.** < 500 ms at p95. If checks are slower, cache them.
- **Idempotent.** Never writes, never rotates, never notifies.

Success:

```json
{"status":"ok","timestamp":"2026-04-10T09:14:22Z","version":"1.4.2",
 "checks":{"database":{"status":"ok"},"disk":{"status":"ok"},
           "php_fpm":{"status":"ok"}}}
```

Failure (HTTP 503):

```json
{"status":"down","timestamp":"2026-04-10T09:14:22Z","version":"1.4.2",
 "checks":{"database":{"status":"fail","error":"connection refused"},
           "disk":{"status":"ok","used_percent":62},
           "php_fpm":{"status":"ok"}}}
```

## Checks to include

A `/health` that only returns `{"status":"ok"}` is worse than
useless — it lies. At minimum:

| Check | What it verifies | Critical? |
|---|---|---|
| Database | `SELECT 1` with ≤ 500 ms timeout | Yes |
| Disk | Data partition < 90% used | Yes |
| Required services | `redis-server`, `php-fpm` process present | Yes |
| Queue depth | Background queue below ceiling | Depends |
| Dependent API | HEAD/HEAD `/health` with 1 s timeout | Degrade |
| Cache | Redis `PING` with 200 ms timeout | Degrade |
| Cert expiry | Local cert not within 7 days of expiry | Degrade |

A check is **critical** if serving traffic is broken without it (DB
yes, cache no). `degraded` keeps HTTP 200 — the load balancer does
not drain the backend, but the monitoring alerts still fire on the
per-check status in the body.

Do NOT include: external internet reachability, "CPU < 80%" (that
is a metric), "served a request in the last minute" (circular), or
anything that cannot complete inside the latency budget.

## Public vs internal endpoints

**Public `/health`** — exposed via the load balancer.
Unauthenticated. Minimal body: `200 {"status":"ok"}` or
`503 {"status":"down"}`. No version numbers, no dependency
details, no hostnames, no stack traces.

**Internal `/health/detail`** — exposed only on loopback, a private
VPC, or behind IP allow-list / basic auth / mTLS. Full body:
per-check status, timing, version, commit SHA, dependency versions.

Rationale: the detailed payload is reconnaissance gold for an
attacker (framework, DB, downstream services, internal hostnames,
version). The public `/health` reveals nothing except up or down.

## Nginx location block

`/etc/nginx/snippets/health.conf`:

```nginx
# Public health endpoint — minimal body, short timeout
location = /health {
    access_log off;
    default_type application/json;
    fastcgi_pass   unix:/run/php/php8.3-fpm.sock;
    fastcgi_param  SCRIPT_FILENAME  /var/www/_health/health.php;
    fastcgi_param  HEALTH_MODE      public;
    include        fastcgi_params;
    fastcgi_read_timeout 2s;
    fastcgi_connect_timeout 1s;
}

# Internal detailed endpoint — IP allow-list
location = /health/detail {
    access_log off;
    default_type application/json;
    allow 10.0.0.5;        # monitoring host
    allow 10.0.0.6;        # jump host
    deny  all;
    fastcgi_pass   unix:/run/php/php8.3-fpm.sock;
    fastcgi_param  SCRIPT_FILENAME  /var/www/_health/health.php;
    fastcgi_param  HEALTH_MODE      detail;
    include        fastcgi_params;
    fastcgi_read_timeout 5s;
}
```

Include from each server block that should expose health:
`include snippets/health.conf;`. `access_log off` is deliberate —
at one probe per 10 s per monitor, health noise drowns real
traffic; track probes via shipper metrics instead.

## PHP reference implementation

`/var/www/_health/health.php`:

```php
<?php
declare(strict_types=1);
header('Content-Type: application/json');
header('Cache-Control: no-store, max-age=0');

$mode = $_SERVER['HEALTH_MODE'] ?? 'public';
$checks = [];
$overall = 'ok';

// Check 1: database reachable
try {
    $pdo = new PDO('mysql:host=127.0.0.1;dbname=app;charset=utf8mb4',
        'health', getenv('HEALTH_DB_PASS') ?: '', [
            PDO::ATTR_TIMEOUT => 1,
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
    $pdo->query('SELECT 1')->fetchColumn();
    $checks['database'] = ['status' => 'ok'];
} catch (Throwable $e) {
    $checks['database'] = ['status' => 'fail', 'error' => 'unreachable'];
    $overall = 'down';
}

// Check 2: disk not full
$free = @disk_free_space('/var/www');
$total = @disk_total_space('/var/www');
$used = ($total > 0) ? (int) round(100 * (1 - $free / $total)) : 100;
if ($used >= 90) {
    $checks['disk'] = ['status' => 'fail', 'used_percent' => $used];
    $overall = 'down';
} else {
    $checks['disk'] = ['status' => 'ok', 'used_percent' => $used];
}

// Check 3: upstream API (degrade, not fail)
$ch = curl_init('https://api.internal.example.com/health');
curl_setopt_array($ch, [CURLOPT_NOBODY => true, CURLOPT_TIMEOUT_MS => 1000,
    CURLOPT_CONNECTTIMEOUT_MS => 500, CURLOPT_SSL_VERIFYPEER => true,
    CURLOPT_RETURNTRANSFER => true]);
curl_exec($ch);
$upCode = curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
curl_close($ch);
if ($upCode >= 200 && $upCode < 400) {
    $checks['upstream_api'] = ['status' => 'ok'];
} else {
    $checks['upstream_api'] = ['status' => 'degraded', 'http_code' => $upCode];
    if ($overall === 'ok') { $overall = 'degraded'; }
}

// Build response — strip details in public mode
$body = ['status' => $overall, 'timestamp' => gmdate('c')];
if ($mode === 'detail') {
    $body['version']  = trim(@file_get_contents(__DIR__ . '/VERSION') ?: 'unknown');
    $body['hostname'] = gethostname();
    $body['checks']   = $checks;
} else {
    $body['checks'] = array_map(fn($c) => ['status' => $c['status']], $checks);
}

// 200 for ok/degraded (keep in rotation), 503 for down
http_response_code($overall === 'down' ? 503 : 200);
echo json_encode($body, JSON_UNESCAPED_SLASHES);
```

Notes: DB user `health` has minimum privilege (`SELECT` only) and
its password comes via `fastcgi_param HEALTH_DB_PASS` from a
secret file, never inline. `CURLOPT_TIMEOUT_MS=1000` caps the
upstream check at 1 s — never let a dependency wedge your own
`/health`. `degraded` returns 200 so the load balancer keeps the
backend in rotation; monitoring alerts separately on
`status=degraded`. Node.js, Python, and Go follow the same shape:
a list of check functions each returning `{status, error?}`,
aggregated into one response with 200 or 503.

## Nginx-only health: trade-offs

For a static site with no PHP/Node runtime, Nginx alone can expose
`stub_status`:

```nginx
location = /health {
    access_log off;
    stub_status;
    allow 127.0.0.1;
    allow 10.0.0.5;
    deny all;
}
```

It returns 200 as long as Nginx is running — strictly weaker than
the full contract. No DB check, no disk check, no JSON body.
`stub_status` is a Prometheus scrape target (feed it to
`nginx-exporter`), not a health endpoint. Keep it at
`/metrics/nginx` and keep `/health` separate with a real handler.

## Metrics vs health: different things

Conflating `/metrics` and `/health` is the most common beginner
mistake. They are separate handlers on separate URLs, usually on
separate ports (9100 for `node_exporter`, 443 for `/health`).

| | `/metrics` | `/health` |
|---|---|---|
| Consumer | Prometheus | Load balancer, uptime monitor |
| Format | Prometheus exposition text | JSON |
| Content | Hundreds of time-series samples | A handful of boolean checks |
| Size | 10–100 KB | < 500 bytes |
| HTTP status | Always 200 | 200 or 503 |
| Auth | IP allow-list to monitoring host | Public minimal + internal detail |

## Frequency, timeouts, and caching

- **Probe frequency.** Load balancers: every 5–10 s. Uptime
  monitors: every 30–60 s. `blackbox_exporter`: every 15 s.
- **Probe timeout.** 2 s for the whole HTTP request.
- **Fail threshold.** Three consecutive failures before draining
  (load balancer default). One failure is too noisy.
- **Caching.** If a check is expensive, cache the aggregated result
  in APCu or a file on tmpfs for 2–5 s:

```php
$cacheFile = '/run/health/cache.json';
if (is_readable($cacheFile) && (time() - filemtime($cacheFile)) < 3) {
    $body = json_decode(file_get_contents($cacheFile), true);
} else {
    $body = runAllChecks();
    @file_put_contents($cacheFile, json_encode($body), LOCK_EX);
}
```

`/run/health` is tmpfs, RAM-backed, reboot-volatile. Never cache
longer than 5 s — the point is fresh health.

## Integration with blackbox_exporter

On the monitoring host, configure `blackbox_exporter` to probe
every `/health` and feed the result to Prometheus:

```yaml
# blackbox.yml
modules:
  http_health_2xx:
    prober: http
    timeout: 3s
    http:
      method: GET
      valid_status_codes: [200]
      fail_if_body_not_matches_regexp: ['"status":"ok"']
      tls_config: { insecure_skip_verify: false }

# prometheus.yml
- job_name: blackbox-health
  metrics_path: /probe
  params: { module: [http_health_2xx] }
  static_configs:
    - targets: [https://example.com/health, https://api.example.com/health]
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: blackbox-exporter.internal:9115
```

Alert when `probe_success == 0` for 3 minutes. This closes the
loop: `/health` on the server → blackbox on the monitoring host →
Prometheus → Alertmanager → on-call. A failing backend becomes a
page in under 5 minutes without anyone SSHing anywhere.

## Sources

- Brian Kemp, *Linux System Administration for the 2020s: The Modern
  Sysadmin Leaving Behind the Culture of Build and Maintain* —
  production readiness criteria (monitoring + logging + security as
  the minimum bar) and the philosophy that every service is part of
  a monitoring stack, not an isolated box.
- Microsoft Azure Architecture Center — "Health Endpoint Monitoring"
  pattern.
- Google SRE Book — Chapter 6, "Monitoring Distributed Systems"
  (black-box vs white-box; the four golden signals).
- Kubernetes documentation — liveness and readiness probes, and why
  they are different.
- Prometheus `blackbox_exporter` — HTTP prober module reference.
- IETF draft `draft-inadarei-api-health-check` — the JSON shape for
  health endpoints that this pattern follows.
