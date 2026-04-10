# PHP-FPM Pool Tuning

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

PHP-FPM is the bottleneck of most PHP-hosting servers: too few workers means requests queue and pages slow down; too many and a traffic spike can OOM-kill the box. This reference walks through every pool setting that actually matters in production on Ubuntu/Debian: choosing a process manager (`dynamic` / `ondemand` / `static`), sizing `pm.max_children` from the RAM budget, wiring up slow logs, securing the listen socket, and tuning Opcache (including PHP 8 JIT). Two complete production pool files appear at the end — one for a WordPress site, one for a Laravel API.

## Table of contents

1. Process manager modes: dynamic / ondemand / static
2. Sizing `pm.max_children` from RAM
3. `pm.start_servers`, `min_spare_servers`, `max_spare_servers`
4. `pm.max_requests` — why you must set it
5. Slow log and request timing
6. Per-pool access log
7. User, group, and listen ownership
8. Unix socket vs TCP listen
9. Opcache tuning (including PHP 8 JIT)
10. Complete pool example — WordPress
11. Complete pool example — Laravel API
12. Sources

---

## 1. Process manager modes

PHP-FPM ships three strategies for spawning and reaping worker processes. You pick exactly one per pool via the `pm =` directive.

### 1.1 `pm = dynamic`

**When to use:** Default choice for web hosting. The master keeps a pool of idle workers ready for incoming requests and grows the pool under load.

- Fast response to sudden traffic (spare workers are already warm).
- Bounded memory — the master kills idle workers once the spare count exceeds `pm.max_spare_servers`.
- Requires you to set four variables: `pm.max_children`, `pm.start_servers`, `pm.min_spare_servers`, `pm.max_spare_servers`.

### 1.2 `pm = ondemand`

**When to use:** Low-traffic sites, dev servers, or many low-traffic pools on one box where RAM is tight.

- No workers exist until a request arrives.
- First request on a cold pool pays a fork cost (~20–100 ms).
- Idle workers die after `pm.process_idle_timeout`.
- Only `pm.max_children` and `pm.process_idle_timeout` are used; the spare settings are ignored.

```ini
pm = ondemand
pm.max_children = 20
pm.process_idle_timeout = 10s
pm.max_requests = 500
```

### 1.3 `pm = static`

**When to use:** Single-site servers where you know exactly how many workers you want and you want zero fork overhead during a request. Typical for a dedicated API box.

- `pm.max_children` workers are spawned at boot and stay forever (modulo `pm.max_requests` recycling).
- Lowest latency, highest baseline RAM consumption.

```ini
pm = static
pm.max_children = 50
pm.max_requests = 1000
```

---

## 2. Sizing `pm.max_children` from RAM

The cap must never exceed the RAM you can actually afford to give PHP. Oversized pools cause OOM kills that take down the entire stack.

### Formula

```
pm.max_children = (Total RAM − OS/Nginx/MySQL reserve) ÷ average worker RSS
```

**OS/Nginx/MySQL reserve** is what the rest of the stack needs to stay healthy. Sensible defaults on a general-purpose web server:

| Server RAM | Reserve for OS + Nginx + MySQL + Redis | Budget for PHP-FPM |
|---|---|---|
| 1 GB   | 512 MB | 512 MB |
| 2 GB   | 800 MB | 1.2 GB |
| 4 GB   | 1.5 GB | 2.5 GB |
| 8 GB   | 2.5 GB | 5.5 GB |
| 16 GB  | 4 GB   | 12 GB  |

**Average worker RSS** depends on the framework — measure with `ps` on a warm server:

```bash
# Average resident memory of PHP-FPM workers (MB)
ps --no-headers -o rss -C php-fpm8.3 | awk '{s+=$1} END {printf "%.0f MB\n", s/NR/1024}'
```

Typical values:

| Framework             | RSS per worker |
|-----------------------|----------------|
| Plain PHP (no framework) | 20–40 MB  |
| WordPress                | 40–80 MB  |
| Drupal                   | 60–120 MB |
| Laravel / Symfony        | 60–120 MB |
| Magento 2                | 150–250 MB |

### Worked examples

**1 GB VPS, WordPress (60 MB per worker):**
```
(1024 − 512) / 60 = 8.5  →  pm.max_children = 8
```

**2 GB VPS, Laravel (90 MB per worker):**
```
(2048 − 800) / 90 = 13.8  →  pm.max_children = 13
```

**4 GB VPS, WordPress (60 MB):**
```
(4096 − 1500) / 60 = 43.2  →  pm.max_children = 40
```

**8 GB dedicated, Laravel (100 MB) + separate DB box:**
```
(8192 − 1000) / 100 = 71.9  →  pm.max_children = 70
```

Always round **down**, never up. Leave headroom for memory fragmentation and request spikes.

---

## 3. `pm.start_servers`, `min_spare_servers`, `max_spare_servers`

Only used when `pm = dynamic`. PHP-FPM refuses to start if these are inconsistent.

**Rules:**
- `pm.min_spare_servers <= pm.start_servers <= pm.max_spare_servers`
- `pm.max_spare_servers < pm.max_children`

**Recommended ratios (work for most sites):**

```ini
pm.start_servers     = pm.max_children * 0.20      # 20% of cap at boot
pm.min_spare_servers = pm.max_children * 0.10      # always keep 10% idle
pm.max_spare_servers = pm.max_children * 0.40      # reap anything above 40% idle
```

So for `pm.max_children = 20`:

```ini
pm.max_children      = 20
pm.start_servers     = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 8
```

For `pm.max_children = 40`:

```ini
pm.max_children      = 40
pm.start_servers     = 8
pm.min_spare_servers = 4
pm.max_spare_servers = 16
```

---

## 4. `pm.max_requests` — why you must set it

`pm.max_requests` tells each worker to exit after handling N requests. A fresh worker replaces it. This is the cheapest possible defence against PHP extensions that leak memory.

```ini
pm.max_requests = 500        # recycle after 500 requests
```

- Default `0` means never recycle — a leaky extension will slowly consume all available RAM.
- 500–1000 is fine for most sites. Lower to 200 if the app has known leaks (very old WordPress plugins, buggy Composer packages).
- Don't set it absurdly low (< 100) or you'll spend CPU forking workers.

Verify the setting is taking effect:

```bash
# Watch workers be born and die
sudo journalctl -u php8.3-fpm -f | grep -i child
```

---

## 5. Slow log and request timing

The slow log captures a full PHP backtrace for any request that exceeds a time threshold. Indispensable for finding the one query that's killing the site.

```ini
slowlog = /var/log/php/<site>.slow.log
request_slowlog_timeout = 5s
```

Create the log directory and set permissions:

```bash
sudo mkdir -p /var/log/php
sudo chown www-data:www-data /var/log/php
sudo chmod 755 /var/log/php
```

Example slow log entry:

```
[08-Apr-2026 14:23:11]  [pool example] pid 12345
script_filename = /var/www/html/example.com/public/index.php
[0x00007f5c4a1e2e78] mysqli_query() /var/www/html/example.com/app/Models/Report.php:42
[0x00007f5c4a1e2b60] Report->generate() /var/www/html/example.com/app/Http/Controllers/ReportController.php:87
...
```

Also set `request_terminate_timeout` slightly above your Nginx `fastcgi_read_timeout` so PHP kills runaway requests:

```ini
request_terminate_timeout = 120s
```

---

## 6. Per-pool access log

The access log shows which PHP script a request hit and how long it took — useful for auditing and for correlating with Nginx logs.

```ini
access.log = /var/log/php/<site>.access.log
access.format = "%R - %u %t \"%m %r%Q%q\" %s %f %{mili}d %{kilo}M %C%%"
```

Placeholders:
- `%R` remote address
- `%t` timestamp
- `%m` HTTP method
- `%r` URI
- `%s` status code
- `%f` script filename
- `%{mili}d` duration in milliseconds
- `%{kilo}M` peak memory in KB
- `%C%%` CPU usage percentage

Disable in production if log volume is too high (`access.log = /dev/null`).

---

## 7. User, group, and listen ownership

One pool per site, one Unix user per pool. This is the core of per-site isolation: a PHP RCE in site A cannot read site B's files or config.

```ini
user  = site-a
group = site-a

listen = /run/php/site-a.sock
listen.owner = www-data        # who can open the socket (Nginx user)
listen.group = www-data
listen.mode  = 0660            # rw for owner/group, nothing for others
```

Create the unprivileged user with no login shell and no home directory:

```bash
sudo adduser --system --no-create-home --group --shell /usr/sbin/nologin site-a
sudo chown -R site-a:www-data /var/www/html/site-a
sudo find /var/www/html/site-a -type d -exec chmod 2750 {} \;
sudo find /var/www/html/site-a -type f -exec chmod 640 {} \;
```

The `2750` on directories sets the setgid bit so new files inherit the group.

---

## 8. Unix socket vs TCP listen

**Unix socket** (default on Ubuntu/Debian):

```ini
listen = /run/php/site-a.sock
```

- Faster — no TCP/IP stack overhead.
- Can't cross hosts.
- File-level permissions via `listen.owner`/`listen.group`/`listen.mode`.
- Preferred for same-host Nginx + PHP-FPM.

**TCP listen:**

```ini
listen = 127.0.0.1:9000
listen.allowed_clients = 127.0.0.1
```

- Required when PHP-FPM runs in a container or on a different host.
- Slower than a socket.
- Must be firewalled or bound to loopback — never expose 9000 publicly.

---

## 9. Opcache tuning (including PHP 8 JIT)

Opcache stores compiled bytecode in shared memory so PHP doesn't re-parse files on every request. It is the single biggest performance win on any PHP site and is enabled by default on Ubuntu's `php-fpm` package — but the defaults are tiny. Tune in `/etc/php/8.3/fpm/conf.d/10-opcache.ini`.

```ini
opcache.enable = 1
opcache.enable_cli = 0

; Memory budget for compiled bytecode (MB)
opcache.memory_consumption = 256

; Memory for interned strings (MB)
opcache.interned_strings_buffer = 16

; Max number of files that can be cached. Must exceed the total
; number of .php files in your application.
;   find /var/www -type f -name '*.php' | wc -l
opcache.max_accelerated_files = 20000

; Don't waste memory tracking wasted memory
opcache.max_wasted_percentage = 10

; 0 = never check file timestamps (best perf, deploy via FPM reload)
; 1 = check every request (dev only)
; Production: 0 + reload php-fpm on deploy
opcache.validate_timestamps = 0
opcache.revalidate_freq = 0

; Save memory — strip docblocks from cached bytecode
opcache.save_comments = 1            ; set to 0 only if no framework uses docblock annotations

; Fast shutdown path (uses request's memory manager for cleanup)
opcache.fast_shutdown = 1

; PHP 8+ JIT — real win on CPU-bound code
; 0     = disabled
; 1205  = function-level, tracing (recommended for web)
; 1255  = full tracing JIT
opcache.jit_buffer_size = 128M
opcache.jit = 1205
```

**Deploy workflow with `validate_timestamps = 0`:** after a `git pull`, you must reload PHP-FPM to flush the Opcache or clients will keep seeing the old code.

```bash
sudo systemctl reload php8.3-fpm
```

Verify Opcache is healthy:

```bash
sudo apt install -y php-cli
php -r 'print_r(opcache_get_status(false));'           # won't show FPM cache; use a web script
```

Web script to check FPM's cache:

```php
<?php header('Content-Type: text/plain'); print_r(opcache_get_status()); ?>
```

Look for:
- `memory_usage.used_memory` vs `memory_usage.free_memory` — raise `memory_consumption` if free drops below 20%.
- `opcache_statistics.num_cached_scripts` vs `opcache_statistics.max_cached_keys` — raise `max_accelerated_files` if near the limit.
- `opcache_statistics.oom_restarts` — should be 0. Non-zero means your cache is too small.

### JIT notes

- JIT helps CPU-bound code (image processing, mathematics, string parsing) measurably — 10–40% on micro-benchmarks.
- For typical database-bound web apps the gain is usually 2–8%.
- `opcache.jit = 1205` is the safe production choice (function-level tracing). Try `1255` only after load-testing.
- If you see segfaults after enabling JIT, drop to `opcache.jit = 0` and check the PHP bug tracker for your extension.

---

## 10. Complete pool example — WordPress

`/etc/php/8.3/fpm/pool.d/blog.conf`

```ini
[blog]
user  = blog
group = blog

listen = /run/php/blog.sock
listen.owner = www-data
listen.group = www-data
listen.mode  = 0660

; Dynamic — WordPress traffic is bursty
pm = dynamic
pm.max_children      = 20
pm.start_servers     = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 8
pm.max_requests      = 500
pm.process_idle_timeout = 30s

; Slow log
slowlog = /var/log/php/blog.slow.log
request_slowlog_timeout = 5s
request_terminate_timeout = 120s

; Access log
access.log = /var/log/php/blog.access.log
access.format = "%R - %u %t \"%m %r%Q%q\" %s %f %{mili}d %{kilo}M %C%%"

; Catch stderr
catch_workers_output = yes

; Per-site PHP overrides
php_admin_value[memory_limit]       = 256M
php_admin_value[upload_max_filesize] = 64M
php_admin_value[post_max_size]      = 64M
php_admin_value[max_execution_time] = 60
php_admin_value[max_input_vars]     = 3000
php_admin_value[error_log]          = /var/log/php/blog.error.log
php_admin_flag[log_errors]          = on
php_admin_flag[display_errors]      = off
php_admin_value[date.timezone]      = Africa/Nairobi
php_admin_value[session.save_path]  = /var/lib/php/sessions/blog
php_admin_value[session.gc_maxlifetime] = 1440

; Disable dangerous functions defence in depth
php_admin_value[disable_functions]  = exec,passthru,shell_exec,system,proc_open,popen,curl_multi_exec,parse_ini_file,show_source
```

---

## 11. Complete pool example — Laravel API

`/etc/php/8.3/fpm/pool.d/api.conf`

```ini
[api]
user  = api
group = api

listen = /run/php/api.sock
listen.owner = www-data
listen.group = www-data
listen.mode  = 0660

; Static — predictable API traffic, lowest latency
pm = static
pm.max_children = 40
pm.max_requests = 1000

; Slow log
slowlog = /var/log/php/api.slow.log
request_slowlog_timeout = 3s
request_terminate_timeout = 60s

; Access log off — already logged by the Laravel app
access.log = /dev/null

catch_workers_output = yes
clear_env = no                     ; so EnvironmentFile-style .env is visible

; Per-site PHP overrides
php_admin_value[memory_limit]       = 256M
php_admin_value[upload_max_filesize] = 16M
php_admin_value[post_max_size]      = 16M
php_admin_value[max_execution_time] = 30
php_admin_value[error_log]          = /var/log/php/api.error.log
php_admin_flag[log_errors]          = on
php_admin_flag[display_errors]      = off
php_admin_value[date.timezone]      = Africa/Nairobi
php_admin_value[opcache.memory_consumption] = 256
php_admin_value[opcache.max_accelerated_files] = 20000
php_admin_value[opcache.validate_timestamps] = 0

; Tight function blacklist for an API that never shells out
php_admin_value[disable_functions]  = exec,passthru,shell_exec,system,proc_open,popen,pcntl_exec,curl_multi_exec,parse_ini_file,show_source,eval
```

Reload and verify both pools:

```bash
sudo php-fpm8.3 -t
sudo systemctl reload php8.3-fpm
ls -la /run/php/                   # blog.sock and api.sock should both exist with 0660
```

---

## 12. Sources

- Atef, Ghada. *Mastering Ubuntu: A Comprehensive Guide to Linux's Favorite.* 2023 — Chapter VI (Ubuntu for Servers) on web server and PHP installation.
- Canonical. *Ubuntu Server Guide — Linux 20.04 LTS (Focal).* 2020 — PHP chapter.
- PHP-FPM official docs at <https://www.php.net/manual/en/install.fpm.configuration.php>.
- Opcache reference at <https://www.php.net/manual/en/book.opcache.php>, including PHP 8 JIT configuration.
- `man 8 php-fpm8.3`, `/etc/php/8.3/fpm/pool.d/www.conf` as shipped by the Debian/Ubuntu PHP packaging.
