# Nginx Directive Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

A practical reference for the Nginx directives that matter in production on a dual-stack Ubuntu/Debian server. Each directive is shown with the syntax you will actually type, the context it belongs in, its default, and a worked example. The focus is the subset that drives the Nginx+Apache+PHP-FPM+Node.js pattern — not the full 900-directive manual. When a directive has subtle behaviour (the `add_header` "always" trap, `try_files` fallthrough, `proxy_http_version 1.1` + keepalive), the gotcha is called out inline.

## Table of contents

1. Server block fundamentals
2. Location matching rules
3. `rewrite` vs `return`
4. `try_files` patterns (PHP front-controller and SPA)
5. `proxy_pass` and proxy directives
6. `fastcgi_pass` and FastCGI directives
7. Rate limiting (`limit_req_zone`, `limit_req`)
8. Connection limiting (`limit_conn_zone`, `limit_conn`)
9. `error_page`
10. Logging (`access_log`, `error_log`, `log_format`)
11. `add_header` and the `always` flag
12. Sources

---

## 1. Server block fundamentals

### `listen`

- **Context:** `server`
- **Syntax:** `listen address[:port] [ssl] [http2] [default_server] [reuseport];`
- **Purpose:** Which socket this server block binds to.

```nginx
listen 80;
listen [::]:80;                           # IPv6
listen 443 ssl http2;
listen [::]:443 ssl http2;
listen 127.0.0.1:8080;                    # loopback-only (Apache backend)
listen 80 default_server;                 # catch-all for unknown hostnames
```

**Gotchas:**
- The first server block for a given `listen` address on a port becomes the implicit `default_server` if you don't mark one explicitly. Always define a catch-all so unknown `Host:` headers don't land on your first alphabetical vhost.
- `http2` requires `ssl` in Nginx ≥ 1.25. On older versions the syntax is `listen 443 ssl; http2 on;` inside the server block.

### `server_name`

- **Context:** `server`
- **Syntax:** `server_name name1 name2 ...;`

```nginx
server_name example.com www.example.com;
server_name *.example.com;                # wildcard subdomains
server_name ~^api-(?<env>.+)\.example\.com$;  # regex capture
server_name _;                            # match anything (catch-all)
```

Order of precedence when multiple servers match:
1. Exact name (`example.com`)
2. Longest wildcard starting with `*` (`*.example.com`)
3. Longest wildcard ending with `*` (`mail.*`)
4. First matching regex in config order

### `root` and `index`

- **Context:** `http`, `server`, `location`
- **`root`** sets the filesystem prefix for `$uri`. **`alias`** replaces the matched location prefix. Use `root` 95% of the time.

```nginx
root /var/www/html/example.com/public;
index index.php index.html;
```

**Gotcha:** `root` inside a `location` block appends the location's URI; `alias` does not. `root /var/www; location /img/` maps `/img/logo.png` to `/var/www/img/logo.png`. `alias /var/www/static/; location /img/` maps the same URL to `/var/www/static/logo.png`.

---

## 2. Location matching rules

Nginx picks one location per request using a strict priority order:

| Priority | Modifier | Meaning | Example |
|:-:|:-:|---|---|
| 1 | `=` | Exact match — fastest | `location = /favicon.ico` |
| 2 | `^~` | Longest prefix, stop regex | `location ^~ /static/` |
| 3 | `~` / `~*` | Regex (case-sensitive / insensitive), first match wins | `location ~* \.(jpg\|png)$` |
| 4 | (none) | Longest prefix, regexes may still override | `location /api/` |

Worked example:

```nginx
location = /healthz { return 200 "ok\n"; }             # exact, wins over everything
location ^~ /static/ { expires 1y; }                   # prefix, no regex re-check
location ~* \.php$ { include snippets/fastcgi-php.conf; }
location ~* \.(jpg|css|js)$ { expires 30d; }
location / { try_files $uri $uri/ /index.php?$query_string; }
```

**Gotcha:** `location /` is the weakest possible match — any prefix or regex beats it. Beginners often put `try_files` in `location /` and wonder why `.php` requests never hit it; the regex location catches them first.

---

## 3. `rewrite` vs `return`

Both change the URL a client or Nginx sees. **Prefer `return` — it is faster, cannot loop, and its intent is obvious.**

```nginx
# HTTP → HTTPS redirect — always use `return`
server {
    listen 80;
    server_name example.com;
    return 301 https://$host$request_uri;
}

# Canonical domain (www → apex) — `return`
if ($host = www.example.com) { return 301 https://example.com$request_uri; }

# Internal URL normalisation — `rewrite`
rewrite ^/old-blog/(.*)$ /blog/$1 permanent;          # external redirect (301)
rewrite ^/api/v1/(.*)$ /api/v2/$1 last;               # internal rewrite, restart processing
rewrite ^/admin$ /admin/ break;                        # internal rewrite, stay in this location
```

**Flags:**
- `last` — stop processing rewrites in this block, restart location matching on the new URI.
- `break` — stop processing rewrites, keep serving from the current location.
- `redirect` — emit 302 to the client.
- `permanent` — emit 301 to the client.

**Gotcha:** `if` blocks in Nginx are evil (see Nginx wiki "IfIsEvil"). Use `return` in a `server` block, or map variables with `map`, instead of `if ... { rewrite ... }` whenever possible.

---

## 4. `try_files` patterns

`try_files` checks each argument in order as a filesystem path; the last argument is either a URI (recursive match) or a status code.

### 4.1 PHP front controller (Laravel/Symfony/WordPress)

```nginx
location / {
    try_files $uri $uri/ /index.php?$query_string;
}

location ~ \.php$ {
    try_files $uri =404;                  # reject requests for non-existent .php files
    include snippets/fastcgi-php.conf;
}
```

The `$uri =404` inside the `.php` location is the single most important anti-exploit pattern in PHP hosting. Without it, requests like `/uploads/evil.jpg/x.php` get forwarded to PHP-FPM with `SCRIPT_FILENAME=/uploads/evil.jpg` and PHP happily executes the JPEG as PHP. The `=404` line stops that dead.

### 4.2 SPA (Astro with client-side router, React, Vue)

```nginx
location / {
    try_files $uri $uri/ $uri.html /index.html;
}
```

The `$uri.html` entry lets Astro's file-based routes work (`/about` → `/about.html`); the final `/index.html` is the client-side routing fallback.

### 4.3 Static site with custom 404

```nginx
location / {
    try_files $uri $uri/ =404;
}
error_page 404 /404.html;
```

---

## 5. `proxy_pass` and proxy directives

### `proxy_pass`

- **Context:** `location`
- **Syntax:** `proxy_pass http[s]://host[:port][/path];`

```nginx
# Simple — pass through with path intact
location /api/ {
    proxy_pass http://127.0.0.1:3001;
}

# Strip /api/ from the path before proxying
location /api/ {
    proxy_pass http://127.0.0.1:3001/;    # trailing slash = rewrite prefix
}

# Upstream pool with keepalive
upstream backend {
    server 127.0.0.1:3001;
    server 127.0.0.1:3002;
    keepalive 32;
}
location / {
    proxy_pass http://backend;
}
```

**Gotcha:** The presence or absence of a **trailing slash** on `proxy_pass` changes everything. `proxy_pass http://x;` preserves the original URI; `proxy_pass http://x/;` replaces the location prefix. This is the #1 source of 404s behind a reverse proxy.

### `proxy_set_header`

Clear and reset headers that the upstream needs. By default Nginx forwards almost nothing useful.

```nginx
proxy_set_header Host              $host;
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host  $host;
proxy_set_header X-Forwarded-Port  $server_port;
```

### `proxy_http_version 1.1` + `Connection ""`

Required to enable upstream keepalive. Without both lines, Nginx opens a fresh TCP connection to the backend on every request.

```nginx
proxy_http_version 1.1;
proxy_set_header Connection "";
```

### `proxy_buffering`

- `on` (default) — Nginx reads the full upstream response into its own buffers before streaming to the client. Good for throughput.
- `off` — Nginx streams as bytes arrive. Required for Server-Sent Events, long-polling, and progress indicators.

```nginx
location /events {
    proxy_pass http://backend;
    proxy_buffering off;
    proxy_cache off;
    proxy_read_timeout 24h;
}
```

### Timeouts

```nginx
proxy_connect_timeout 5s;                  # TCP connect to upstream
proxy_send_timeout    60s;                 # writing the request
proxy_read_timeout    60s;                 # waiting between successive reads
```

Raise `proxy_read_timeout` for long-running requests (PDF generation, report exports); keep `proxy_connect_timeout` low so bad upstreams fail fast.

### `proxy_cache`

```nginx
# Declare cache zone at http{} level
proxy_cache_path /var/cache/nginx/myapp levels=1:2 keys_zone=myapp:10m max_size=1g inactive=60m use_temp_path=off;

# Use it in a location
location /api/public/ {
    proxy_cache myapp;
    proxy_cache_valid 200 301 302 5m;
    proxy_cache_valid 404 1m;
    proxy_cache_use_stale error timeout updating http_500 http_502 http_503 http_504;
    proxy_cache_background_update on;
    proxy_cache_lock on;
    add_header X-Cache-Status $upstream_cache_status always;
    proxy_pass http://backend;
}
```

---

## 6. `fastcgi_pass` and FastCGI directives

### `fastcgi_pass`

```nginx
fastcgi_pass unix:/run/php/php8.3-fpm.sock;    # Unix socket (preferred, same host)
fastcgi_pass 127.0.0.1:9000;                   # TCP (remote PHP-FPM or containers)
```

### `fastcgi_param` (required set)

```nginx
include fastcgi_params;                        # ships with Nginx, sets the 20 common params
fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
fastcgi_param PATH_INFO        $fastcgi_path_info;
fastcgi_param HTTPS            $https if_not_empty;
```

Use `$realpath_root` (resolves symlinks) rather than `$document_root` when your app lives behind a `current` symlink (Capistrano-style deploys).

### `fastcgi_split_path_info`

Splits URIs like `/index.php/foo/bar` into `SCRIPT_NAME=/index.php` and `PATH_INFO=/foo/bar`. Required for apps that rely on PATH_INFO routing.

```nginx
location ~ \.php(/|$) {
    fastcgi_split_path_info ^(.+\.php)(/.+)$;
    try_files $fastcgi_script_name =404;
    fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
    fastcgi_param PATH_INFO       $fastcgi_path_info;
    include fastcgi_params;
}
```

### `fastcgi_read_timeout`

Default 60s. Raise for long-running PHP scripts (CSV export, bulk mail) — but prefer to run those through a queue instead.

```nginx
fastcgi_read_timeout 300s;
```

### Buffering

```nginx
fastcgi_buffer_size     32k;
fastcgi_buffers         16 16k;
fastcgi_busy_buffers_size 64k;
```

Tune upward if the error log complains `an upstream response is buffered to a temporary file`.

---

## 7. Rate limiting

### `limit_req_zone`

- **Context:** `http`
- **Syntax:** `limit_req_zone <key> zone=<name>:<size> rate=<n>r/s|r/m;`

```nginx
# In nginx.conf http{} block
limit_req_zone $binary_remote_addr zone=api_rl:10m   rate=30r/s;   # 30 req/sec per IP
limit_req_zone $binary_remote_addr zone=login_rl:10m rate=5r/m;    # 5 req/min per IP
```

`10m` holds ~160k unique IP states. `$binary_remote_addr` is 4 bytes (IPv4) vs 7 bytes for the textual form — use it.

### `limit_req`

- **Context:** `server`, `location`

```nginx
location /api/ {
    limit_req zone=api_rl burst=60 nodelay;
    # burst=60 → queue up to 60 excess requests
    # nodelay  → process queued requests immediately rather than pacing them
    proxy_pass http://backend;
}

location = /wp-login.php {
    limit_req zone=login_rl burst=5 nodelay;
    limit_req_status 429;
    include snippets/fastcgi-php.conf;
}
```

Without `burst`, any request that exceeds `rate` gets rejected with 503 immediately — too aggressive for web traffic. With `burst=60 nodelay` you let short spikes through without queueing delays.

### `limit_req_log_level` and `limit_req_status`

```nginx
limit_req_log_level warn;                  # what to log when a request is limited
limit_req_status 429;                      # HTTP status returned (default 503)
```

---

## 8. Connection limiting

### `limit_conn_zone` / `limit_conn`

```nginx
# http{} block
limit_conn_zone $binary_remote_addr zone=conn_rl:10m;

# server or location
limit_conn conn_rl 20;                     # max 20 concurrent connections per IP
```

Use for APIs that stream large responses; combine with `limit_req` for full protection.

---

## 9. `error_page`

```nginx
error_page 404 /404.html;
error_page 500 502 503 504 /50x.html;

location = /404.html { root /var/www/html/errors; internal; }
location = /50x.html { root /var/www/html/errors; internal; }

# Catch a backend 502 and serve a cached stale copy, or a custom page:
error_page 502 = @fallback;
location @fallback {
    root /var/www/html/errors;
    try_files /maintenance.html =502;
}
```

The `internal` directive ensures the error page can't be requested directly by clients.

---

## 10. Logging

### `log_format`

- **Context:** `http`

```nginx
log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                '$status $body_bytes_sent "$http_referer" '
                '"$http_user_agent" "$http_x_forwarded_for" '
                'rt=$request_time uct="$upstream_connect_time" '
                'uht="$upstream_header_time" urt="$upstream_response_time"';

log_format json escape=json '{'
    '"time":"$time_iso8601",'
    '"remote_addr":"$remote_addr",'
    '"request":"$request",'
    '"status":$status,'
    '"body_bytes_sent":$body_bytes_sent,'
    '"request_time":$request_time,'
    '"upstream_response_time":"$upstream_response_time",'
    '"http_referer":"$http_referer",'
    '"http_user_agent":"$http_user_agent"'
'}';
```

The `rt`, `uct`, `uht`, `urt` fields are invaluable for diagnosing slow-upstream problems. `escape=json` handles quoted strings safely for log shippers like Promtail or Filebeat.

### `access_log`

```nginx
access_log /var/log/nginx/example.com.access.log main;
access_log /var/log/nginx/example.com.json.log json buffer=32k flush=5s;
access_log off;                                  # disable entirely (static asset locations)
```

### `error_log`

```nginx
error_log /var/log/nginx/example.com.error.log warn;
# levels: debug | info | notice | warn | error | crit | alert | emerg
```

`debug` needs an Nginx built with `--with-debug`; in production use `warn` or `error`.

---

## 11. `add_header` and the `always` flag

`add_header` only applies to responses with status 200, 201, 204, 206, 301, 302, 303, 304, 307, 308 **unless** you add the `always` flag. This is the single biggest footgun in Nginx security config.

```nginx
# WRONG — header is missing on 4xx/5xx responses:
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains";

# RIGHT — header is always emitted:
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
```

Second gotcha: `add_header` **replaces** all inherited headers from parent contexts as soon as you declare one header in a child context. If you set headers globally in `http{}` and then set one header in a `location{}`, the global ones disappear for that location. Fix by re-declaring the full set inside the location, or by consolidating headers into a snippet and including it in both contexts.

```nginx
# BAD — inside the location, only X-Custom is set; HSTS/X-Frame-Options are gone
http {
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    server {
        location /api/ {
            add_header X-Custom "api" always;    # HSTS and X-Frame-Options NOT inherited
        }
    }
}

# GOOD — include the full snippet wherever you need it
location /api/ {
    include snippets/security-headers.conf;
    add_header X-Custom "api" always;
}
```

---

## 12. Sources

- Atef, Ghada. *Mastering Ubuntu: A Comprehensive Guide to Linux's Favorite.* 2023 — Chapter VI (Ubuntu for Servers) sections on web server installation, networking, and service configuration.
- Canonical. *Ubuntu Server Guide — Linux 20.04 LTS (Focal).* 2020 — Nginx / Apache / PHP chapters.
- Nginx official documentation at <https://nginx.org/en/docs/> (ngx_http_core_module, ngx_http_proxy_module, ngx_http_fastcgi_module, ngx_http_rewrite_module, ngx_http_limit_req_module, ngx_http_log_module).
- Nginx wiki "IfIsEvil" — rationale for preferring `return` and `try_files` over `if`.
- `man 8 nginx` on Ubuntu 22.04/24.04.
