# Apache on Port 8080 (PHP Backend)

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Apache is not the public-facing web server in this stack — Nginx is. Apache runs bound to `127.0.0.1:8080` and exists for one reason: to host PHP apps that depend on `.htaccess`, mod_php, or other Apache-specific features. This reference explains the mod_php / PHP-FPM trade-off, gives a production-ready vhost template for port 8080, walks through the `a2en*/a2dis*` workflow, covers Apache-layer hardening, shows how Apache and Nginx coexist safely on the same host, and documents MPM tuning for `event` vs `prefork`.

## Table of contents

1. Why Apache for PHP? (mod_php vs PHP-FPM)
2. Binding Apache to 127.0.0.1:8080 only
3. Apache vhost template for port 8080
4. Enabling mod_rewrite and required modules
5. `AllowOverride` and `.htaccess`
6. `a2ensite` / `a2dissite` / `a2enmod` / `a2dismod` workflow
7. Apache hardening
8. Apache + Nginx coexistence
9. MPM tuning: event vs prefork
10. Sources

---

## 1. Why Apache for PHP? (mod_php vs PHP-FPM)

Two ways to execute PHP under Apache:

### mod_php

Apache loads the PHP interpreter directly as a module. Every Apache worker is a PHP-capable worker.

Pros:
- Full `.htaccess` support including `php_value`, `php_flag`, `php_admin_value`, `php_admin_flag`.
- Zero IPC overhead — PHP runs inside the Apache process.
- Drop-in replacement for legacy shared hosting — every "upload WordPress to /public_html" tutorial assumes this.
- Required by a small number of legacy apps (and a handful of plugins) that rely on `apache_request_headers()` and similar.

Cons:
- Only works with **MPM prefork**, which is single-threaded per process — much higher memory footprint than event.
- You cannot run multiple PHP versions in the same Apache instance.
- Every static asset served by Apache wastes RAM on a PHP interpreter.

### PHP-FPM (via mod_proxy_fcgi)

Apache calls out to a separate PHP-FPM pool over a Unix socket or TCP.

Pros:
- Works with **MPM event** — much lower memory per request.
- Multiple PHP versions side-by-side.
- Per-pool isolation (user, group, limits).
- Same PHP-FPM you already run for Nginx — one interpreter pool, two front ends.

Cons:
- `.htaccess` `php_value`/`php_flag` directives don't work (use per-pool `php_admin_value` instead).
- Slight IPC overhead vs mod_php.

**Recommendation for this stack:** Use PHP-FPM via `mod_proxy_fcgi` under MPM event. The only time to reach for mod_php + prefork is a legacy app you cannot migrate, and even then, prefer to run that app directly under Nginx + PHP-FPM and skip Apache.

---

## 2. Binding Apache to 127.0.0.1:8080 only

Apache on this stack is an internal backend, not a public server. It must be unreachable from the Internet.

Edit `/etc/apache2/ports.conf`:

```apache
# /etc/apache2/ports.conf
Listen 127.0.0.1:8080

<IfModule ssl_module>
    # SSL is terminated at Nginx, not here — leave these blocks empty.
</IfModule>
<IfModule mod_gnutls.c>
</IfModule>
```

Verify after reload:

```bash
sudo systemctl restart apache2
sudo ss -tlnp | grep apache2
# Expect exactly one line:
#   LISTEN 0 511 127.0.0.1:8080 0.0.0.0:* users:(("apache2",...))
```

If you see `0.0.0.0:8080` or `[::]:8080`, you missed an IP in `ports.conf` — fix it before opening the firewall.

---

## 3. Apache vhost template for port 8080

`/etc/apache2/sites-available/<domain>.conf`

```apache
<VirtualHost 127.0.0.1:8080>
    ServerName  <domain>
    ServerAlias www.<domain>
    ServerAdmin admin@<domain>

    DocumentRoot /var/www/html/<folder>

    <Directory /var/www/html/<folder>>
        Options -Indexes +FollowSymLinks
        AllowOverride All              # allow .htaccess
        Require all granted
    </Directory>

    # Hand PHP off to PHP-FPM (per-site pool socket)
    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php/<site>.sock|fcgi://localhost/"
    </FilesMatch>

    # Trust X-Forwarded-* ONLY from loopback (Nginx)
    RemoteIPHeader        X-Forwarded-For
    RemoteIPInternalProxy 127.0.0.1

    # Override the %h placeholder in LogFormat so the log shows the real client IP
    LogFormat "%a %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" proxy-combined
    CustomLog ${APACHE_LOG_DIR}/<domain>-access.log proxy-combined
    ErrorLog  ${APACHE_LOG_DIR}/<domain>-error.log

    # Hide server details (defence in depth — Nginx also strips them)
    ServerSignature Off

    # Deny dotfiles and secret files at Apache layer
    <FilesMatch "^\.">
        Require all denied
    </FilesMatch>
    <FilesMatch "\.(env|git|sql|bak|htpasswd|htaccess|log|ini|yml|lock|dist)$">
        Require all denied
    </FilesMatch>
</VirtualHost>
```

Enable, test, and reload:

```bash
sudo a2ensite <domain>.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

---

## 4. Enabling mod_rewrite and required modules

The vhost above assumes several modules are enabled. Enable them once per server:

```bash
sudo a2enmod rewrite          # .htaccess RewriteRule
sudo a2enmod proxy            # base proxy
sudo a2enmod proxy_fcgi       # proxy to PHP-FPM
sudo a2enmod setenvif         # conditional logging
sudo a2enmod remoteip         # trust X-Forwarded-For from Nginx
sudo a2enmod headers          # Header directive

# MPM choice — event is the default on modern Ubuntu
sudo a2dismod mpm_prefork 2>/dev/null
sudo a2enmod  mpm_event

sudo systemctl restart apache2
```

Verify loaded modules:

```bash
sudo apache2ctl -M | sort
```

---

## 5. `AllowOverride` and `.htaccess`

`AllowOverride` controls which `.htaccess` directives Apache reads per directory. The choice affects both functionality and performance.

| Setting                  | Meaning                                                     | Use when                                   |
|--------------------------|-------------------------------------------------------------|--------------------------------------------|
| `AllowOverride None`     | Ignore `.htaccess` entirely                                  | Max performance; app has no `.htaccess`    |
| `AllowOverride FileInfo` | Allow MIME, ErrorDocument, Redirect                          | Rarely used directly                       |
| `AllowOverride AuthConfig` | Allow auth directives (basic auth, `Require`)              | Htpasswd-protected admin areas             |
| `AllowOverride Indexes`  | Allow `Options` / `DirectoryIndex`                           | Rare                                       |
| `AllowOverride Limit`    | Allow `Require`, `Order`, `Allow`, `Deny`                    | Rare                                       |
| `AllowOverride Options`  | Allow `Options` + symlink directives                         | Rare (security risk)                       |
| `AllowOverride All`      | Allow everything                                             | Apps that ship a real `.htaccess` (WP, ...) |

**Rule of thumb:** `All` for PHP apps; `None` for any `DocumentRoot` you control yourself. `None` is materially faster because Apache doesn't have to `stat()` a `.htaccess` file in every parent directory on every request.

**.htaccess considerations:**
- `.htaccess` directives are a per-request performance tax. If you can move them into the vhost `<Directory>` block, do it and flip to `AllowOverride None`.
- Under `mod_proxy_fcgi` + PHP-FPM, `php_value` / `php_flag` in `.htaccess` do **not** work. Use per-pool `php_admin_value` instead (see `linux-webstack/references/php-fpm-tuning.md`).
- Deny access to `.htaccess` itself in the vhost (the template above already does via the `^\.` FilesMatch).

---

## 6. `a2ensite` / `a2dissite` / `a2enmod` / `a2dismod` workflow

Debian/Ubuntu's Apache packaging splits `sites-available` and `mods-available` from `sites-enabled` and `mods-enabled`. The `a2*` helpers just manage symlinks between the two.

```bash
# Sites
sudo a2ensite  <domain>.conf        # symlink sites-available/... → sites-enabled/
sudo a2dissite <domain>.conf        # remove symlink
sudo a2query -s                     # list enabled sites

# Modules
sudo a2enmod   rewrite
sudo a2dismod  rewrite
sudo a2query -m                     # list enabled modules

# Required after any enable/disable:
sudo apache2ctl configtest
sudo systemctl reload apache2
```

Deployment sequence for a new PHP vhost:

```bash
sudo nano /etc/apache2/sites-available/<domain>.conf    # write the vhost
sudo a2ensite <domain>.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
curl -H "Host: <domain>" http://127.0.0.1:8080/          # smoke-test the backend directly
```

To take a site offline (maintenance, DNS switch):

```bash
sudo a2dissite <domain>.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
```

---

## 7. Apache hardening

The following belong in `/etc/apache2/conf-available/hardening.conf`. Enable with `sudo a2enconf hardening`.

```apache
# Hide Apache version from Server: header and error pages
ServerTokens Prod
ServerSignature Off

# Disable TRACE / TRACK — CVE-2004-2320, still enabled by default on some builds
TraceEnable Off

# Don't expose ETag inode numbers
FileETag MTime Size

# Disable the default Options bits that allow symlink following where it isn't wanted
<Directory />
    Options -Indexes -FollowSymLinks -ExecCGI
    AllowOverride None
    Require all denied
</Directory>

# Forbid listing of webroots that forgot an index file
<Directory /var/www/>
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

# Limit request body size (matches Nginx client_max_body_size)
LimitRequestBody 67108864    # 64 MB

# Security headers at Apache layer — Nginx sets them too, this is defence in depth
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options        "SAMEORIGIN"
    Header always set Referrer-Policy        "strict-origin-when-cross-origin"
    Header always unset X-Powered-By
    Header always unset Server
</IfModule>
```

Enable and reload:

```bash
sudo a2enconf hardening
sudo apache2ctl configtest
sudo systemctl reload apache2
```

Verify:

```bash
curl -sI http://127.0.0.1:8080/ -H "Host: <domain>" | grep -i "server:\|x-powered"
# Expect minimal Server line and no X-Powered-By
```

---

## 8. Apache + Nginx coexistence

Two HTTP servers on one box is fine — as long as they don't fight for port 80.

**The contract:**
- Nginx owns `0.0.0.0:80` and `0.0.0.0:443`.
- Apache owns `127.0.0.1:8080` and nothing else.
- UFW allows 80/443 inbound; 8080 is **not** in the rule set.
- Every PHP app that needs Apache has a matching Nginx vhost on 80/443 that proxies to `127.0.0.1:8080`.
- PHP apps that don't need Apache run under Nginx + PHP-FPM directly.

**Verify the contract after any config change:**

```bash
# Nginx on 80/443, Apache on 8080 only
sudo ss -tlnp | grep -E 'nginx|apache2'

# UFW should show 80/443 open, never 8080
sudo ufw status verbose

# Apache should not be reachable externally
curl -sI http://<public-ip>:8080/ --max-time 3 || echo "(good — connection refused/blocked)"
```

**Boot order:** both services are systemd units with `After=network-online.target`. If Apache fails to start (config error), Nginx-served sites still work — but any vhost that proxies to Apache returns 502 until Apache recovers.

---

## 9. MPM tuning: event vs prefork

The MPM (Multi-Processing Module) controls how Apache forks workers.

### MPM event (default, recommended)

Hybrid multi-process, multi-threaded. Each process runs many threads; keep-alive connections are handled by a dedicated listener thread so idle keep-alives don't tie up request threads.

- Much lower memory per request than prefork.
- Required by modern Apache + PHP-FPM deployments.
- **Not compatible with mod_php.**

### MPM prefork

One process per request, no threading.

- Required by mod_php (PHP is not thread-safe).
- Higher memory per request.
- Use only if you genuinely need mod_php on this box.

### Sizing — MPM event

Edit `/etc/apache2/mods-available/mpm_event.conf`:

```apache
<IfModule mpm_event_module>
    StartServers             2
    MinSpareThreads          25
    MaxSpareThreads          75
    ThreadsPerChild          25
    ThreadLimit              64
    ServerLimit              16
    MaxRequestWorkers        400    # = ServerLimit * ThreadsPerChild
    MaxConnectionsPerChild   10000  # recycle worker after N connections
</IfModule>
```

Formula:
```
MaxRequestWorkers = ServerLimit * ThreadsPerChild
```

Start conservative: `ServerLimit=8`, `ThreadsPerChild=25` → 200 workers. Raise after you know the real RAM footprint of your PHP-FPM pools (Apache itself uses very little memory under event).

### Sizing — MPM prefork

Edit `/etc/apache2/mods-available/mpm_prefork.conf`:

```apache
<IfModule mpm_prefork_module>
    StartServers             5
    MinSpareServers          5
    MaxSpareServers          10
    MaxRequestWorkers        50     # each worker holds a full PHP interpreter
    MaxConnectionsPerChild   500
</IfModule>
```

Because every worker contains a full mod_php interpreter, `MaxRequestWorkers` must be sized from the same RAM formula used for PHP-FPM (`(RAM − reserve) ÷ average worker RSS`). Typical prefork workers under mod_php consume 60–150 MB each.

Apply:

```bash
sudo a2dismod mpm_prefork    # or mpm_event, depending on direction
sudo a2enmod  mpm_event
sudo apache2ctl configtest
sudo systemctl restart apache2
sudo apache2ctl -V | grep MPM
```

Check runtime stats (requires `mod_status` — enable only on loopback):

```bash
sudo a2enmod status
```

```apache
# /etc/apache2/mods-available/status.conf
<Location /server-status>
    SetHandler server-status
    Require local
</Location>
ExtendedStatus On
```

```bash
sudo systemctl reload apache2
curl -s http://127.0.0.1:8080/server-status?auto
```

---

## 10. Sources

- Atef, Ghada. *Mastering Ubuntu: A Comprehensive Guide to Linux's Favorite.* 2023 — Chapter VI on Apache installation and configuration.
- Canonical. *Ubuntu Server Guide — Linux 20.04 LTS (Focal).* 2020 — Apache HTTP server chapter.
- Apache HTTP Server official documentation at <https://httpd.apache.org/docs/2.4/> — `mod_proxy_fcgi`, `mod_remoteip`, `mod_mpm_event`, `mod_mpm_prefork`.
- `man 8 apache2`, `man 8 a2ensite`, `man 8 a2enmod` on Ubuntu 22.04/24.04.
