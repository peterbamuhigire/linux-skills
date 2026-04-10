# Web Stack Config Patterns

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This reference collects every Nginx, Apache, PHP-FPM and systemd config pattern used by the standard dual-stack layout on Ubuntu/Debian servers: Nginx fronts all public traffic on 80/443, Apache runs on 127.0.0.1:8080 as a PHP backend where mod_php is required, PHP-FPM handles direct PHP sites via a Unix socket, and Node.js APIs run as systemd units on loopback ports. Every block here is copy-pasteable on a stock Ubuntu 22.04 / 24.04 server — replace `<domain>`, `<folder>`, and port numbers as marked.

## Table of contents

1. Global nginx.conf tuning
2. Nginx snippets library
3. Pattern A — Astro/static site from /dist
4. Pattern B — PHP app via PHP-FPM socket (direct)
5. Pattern C — PHP app proxied to Apache on 8080
6. Pattern D — Node.js API reverse-proxied to localhost
7. Pattern E — Hybrid Astro front + PHP API backend
8. PHP-FPM per-site pool template
9. Apache vhost on port 8080 (PHP backend)
10. Node.js systemd unit template
11. Catch-all server (reject unknown hostnames)
12. Sources

---

## 1. Global nginx.conf tuning

Edit `/etc/nginx/nginx.conf`. This is the canonical production-tuned version for a single-box server hosting 5–30 sites.

```nginx
user www-data;
worker_processes auto;                    # one worker per CPU core
worker_rlimit_nofile 65535;                # raise FD ceiling above worker_connections
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 4096;               # 4096 conns/worker * cores = total capacity
    multi_accept on;                       # accept many new conns in one event
    use epoll;                             # default on Linux, pin it for clarity
}

http {
    ##
    # Basic settings
    ##
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 1000;
    types_hash_max_size 2048;
    server_tokens off;                     # hide "nginx/1.24.0" from Server header
    server_names_hash_bucket_size 128;     # for long server_name lists

    client_max_body_size 64M;              # max upload size (raise per-site if needed)
    client_body_buffer_size 128k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 16k;
    client_body_timeout 15;
    client_header_timeout 15;
    send_timeout 15;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ##
    # SSL settings (fallback — per-site certs override)
    ##
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    ##
    # Logging
    ##
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';
    access_log /var/log/nginx/access.log main;
    error_log  /var/log/nginx/error.log warn;

    ##
    # Gzip
    ##
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 256;
    gzip_types
        text/plain text/css text/xml text/javascript
        application/javascript application/json application/xml
        application/rss+xml application/atom+xml
        image/svg+xml font/ttf font/otf;

    ##
    # Rate-limit zones (declare here, use in sites)
    ##
    limit_req_zone  $binary_remote_addr zone=api_rl:10m   rate=30r/s;
    limit_req_zone  $binary_remote_addr zone=login_rl:10m rate=5r/m;
    limit_conn_zone $binary_remote_addr zone=conn_rl:10m;

    ##
    # Virtual hosts
    ##
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
```

Apply:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

---

## 2. Nginx snippets library

Put reusable blocks in `/etc/nginx/snippets/` and `include` them from each vhost.

### 2.1 `/etc/nginx/snippets/security-headers.conf`

```nginx
# Modern baseline security headers. Always use the `always` flag so headers
# are emitted even on 4xx/5xx responses.
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Content-Type-Options    "nosniff" always;
add_header X-Frame-Options           "SAMEORIGIN" always;
add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
add_header Permissions-Policy        "camera=(), microphone=(), geolocation=(), interest-cohort=()" always;
add_header X-XSS-Protection          "0" always;
# Content-Security-Policy must be crafted per-app; uncomment and edit to enable.
# add_header Content-Security-Policy "default-src 'self'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline'; script-src 'self'" always;
```

### 2.2 `/etc/nginx/snippets/ssl-params.conf`

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers on;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_session_tickets off;
ssl_stapling on;
ssl_stapling_verify on;
resolver 1.1.1.1 8.8.8.8 valid=300s;
resolver_timeout 5s;
```

### 2.3 `/etc/nginx/snippets/security-dotfiles.conf`

```nginx
location ~ /\.(?!well-known) { deny all; return 404; }
location ~* \.(env|git|sql|bak|backup|old|orig|save|swp|swo|htpasswd|htaccess|log|ini|conf|yaml|yml|lock|dist)$ { deny all; return 404; }
location ~* /(composer\.(json|lock)|package(-lock)?\.json|yarn\.lock|Gemfile(\.lock)?) { deny all; return 404; }
```

### 2.4 `/etc/nginx/snippets/static-files.conf`

```nginx
location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp|avif|woff|woff2|ttf|eot|otf)$ {
    expires 1y;
    add_header Cache-Control "public, immutable" always;
    access_log off;
    try_files $uri =404;
}
```

### 2.5 `/etc/nginx/snippets/fastcgi-php.conf`

```nginx
# Direct PHP-FPM execution — used inside `location ~ \.php$` blocks
fastcgi_pass unix:/run/php/php8.3-fpm.sock;
fastcgi_index index.php;
fastcgi_split_path_info ^(.+\.php)(/.+)$;
fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
fastcgi_param PATH_INFO $fastcgi_path_info;
fastcgi_param HTTPS $https if_not_empty;
include fastcgi_params;
fastcgi_read_timeout 60s;
fastcgi_buffers 16 16k;
fastcgi_buffer_size 32k;
fastcgi_intercept_errors on;
```

### 2.6 `/etc/nginx/snippets/proxy-to-apache.conf`

```nginx
proxy_pass http://127.0.0.1:8080;
proxy_http_version 1.1;
proxy_set_header Host              $host;
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host  $host;
proxy_set_header X-Forwarded-Port  $server_port;
proxy_connect_timeout 15s;
proxy_send_timeout    60s;
proxy_read_timeout    60s;
proxy_buffering       on;
proxy_buffers         16 16k;
proxy_buffer_size     32k;
```

### 2.7 `/etc/nginx/snippets/acme-challenge.conf`

```nginx
# Webroot-style ACME validation — include in every HTTP (port 80) server block
location ^~ /.well-known/acme-challenge/ {
    default_type "text/plain";
    root /var/www/html;
    allow all;
}
```

---

## 3. Pattern A — Astro/static site from /dist

File: `/etc/nginx/sites-available/<domain>.conf`

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name <domain> www.<domain>;

    # ACME before redirect so certbot can validate
    include snippets/acme-challenge.conf;

    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name <domain> www.<domain>;

    root /var/www/html/<folder>/dist;
    index index.html;

    # Certs added by `certbot --nginx -d <domain>` — placeholders shown here:
    # ssl_certificate     /etc/letsencrypt/live/<domain>/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/<domain>/privkey.pem;
    include snippets/ssl-params.conf;
    include snippets/security-headers.conf;
    include snippets/security-dotfiles.conf;

    # Cache static assets aggressively
    include snippets/static-files.conf;

    # SPA fallback — for hash-routed Astro builds this is harmless
    location / {
        try_files $uri $uri/ $uri.html /index.html;
    }

    # Custom 404 page if the build ships one
    error_page 404 /404.html;

    access_log /var/log/nginx/<domain>.access.log main;
    error_log  /var/log/nginx/<domain>.error.log warn;
}
```

---

## 4. Pattern B — PHP app via PHP-FPM socket (direct)

Use when the app is vanilla PHP, WordPress, or a Laravel/Symfony app you are comfortable driving through Nginx + PHP-FPM without Apache's `.htaccess` layer.

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name <domain>;
    include snippets/acme-challenge.conf;
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name <domain>;

    root /var/www/html/<folder>/public;   # Laravel/Symfony use /public; WordPress uses /
    index index.php index.html;

    include snippets/ssl-params.conf;
    include snippets/security-headers.conf;
    include snippets/security-dotfiles.conf;
    include snippets/static-files.conf;

    # Rate-limit login endpoints (5 req/min)
    location = /wp-login.php { limit_req zone=login_rl burst=5 nodelay; include snippets/fastcgi-php.conf; }
    location = /admin/login  { limit_req zone=login_rl burst=5 nodelay; try_files $uri /index.php?$query_string; }

    # Framework front controller pattern
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    # Execute PHP
    location ~ \.php$ {
        try_files $uri =404;
        include snippets/fastcgi-php.conf;
        # Use the per-site pool socket rather than the global www pool:
        fastcgi_pass unix:/run/php/<site>.sock;
    }

    # Deny direct access to upload dirs executing PHP
    location ~* /(uploads|files|media)/.*\.php$ { deny all; return 404; }

    client_max_body_size 64M;
    access_log /var/log/nginx/<domain>.access.log main;
    error_log  /var/log/nginx/<domain>.error.log warn;
}
```

---

## 5. Pattern C — PHP app proxied to Apache on 8080

Use when the app depends on `.htaccess` rewrite rules, mod_php globals, or a legacy extension that assumes Apache. Nginx handles TLS, static assets, and security headers; Apache handles PHP execution.

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name <domain>;
    include snippets/acme-challenge.conf;
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name <domain>;

    root /var/www/html/<folder>;
    index index.php index.html;

    include snippets/ssl-params.conf;
    include snippets/security-headers.conf;
    include snippets/security-dotfiles.conf;

    # Serve static assets directly from Nginx (faster than proxying)
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp|woff|woff2|ttf)$ {
        expires 1y;
        add_header Cache-Control "public, immutable" always;
        try_files $uri @apache;
    }

    # Everything else proxies to Apache on 8080
    location / {
        try_files $uri @apache;
    }

    location @apache {
        include snippets/proxy-to-apache.conf;
    }

    # PHP must never be served by Nginx in this pattern — let Apache handle it
    location ~ \.php$ {
        include snippets/proxy-to-apache.conf;
    }

    client_max_body_size 64M;
    access_log /var/log/nginx/<domain>.access.log main;
    error_log  /var/log/nginx/<domain>.error.log warn;
}
```

---

## 6. Pattern D — Node.js API reverse-proxied to localhost

```nginx
# Upstream with keepalive — reuse TCP connections to the Node process
upstream myapp_api {
    server 127.0.0.1:3001;
    keepalive 32;
}

server {
    listen 80;
    listen [::]:80;
    server_name api.<domain>;
    include snippets/acme-challenge.conf;
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name api.<domain>;

    include snippets/ssl-params.conf;
    include snippets/security-headers.conf;

    # Rate-limit API (30 req/s burst 60)
    location / {
        limit_req zone=api_rl burst=60 nodelay;
        limit_conn conn_rl 20;

        proxy_pass http://myapp_api;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection        "";       # enable upstream keepalive
        proxy_connect_timeout 5s;
        proxy_read_timeout    60s;
        proxy_send_timeout    60s;
        proxy_buffering       off;                   # stream responses (for SSE)
    }

    # WebSocket upgrade passthrough
    location /ws {
        proxy_pass http://myapp_api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host       $host;
        proxy_read_timeout 3600s;
    }

    client_max_body_size 16M;
    access_log /var/log/nginx/api.<domain>.access.log main;
    error_log  /var/log/nginx/api.<domain>.error.log warn;
}
```

---

## 7. Pattern E — Hybrid Astro front + PHP API backend

Astro SSG serves the marketing/front pages from `/dist`; requests under `/api/` proxy to Apache+PHP on 8080.

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name <domain>;
    include snippets/acme-challenge.conf;
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name <domain>;

    root /var/www/html/<folder>/dist;
    index index.html;

    include snippets/ssl-params.conf;
    include snippets/security-headers.conf;
    include snippets/security-dotfiles.conf;
    include snippets/static-files.conf;

    # PHP API backend (Apache on 8080)
    location /api/ {
        limit_req zone=api_rl burst=40 nodelay;
        # Rewrite URI so Apache sees /api/... as part of its DocumentRoot
        include snippets/proxy-to-apache.conf;
    }

    # Block execution of any .php inside /dist — Astro build should never have any
    location ~ ^/(?!api/).*\.php$ { deny all; return 404; }

    # Static front end
    location / {
        try_files $uri $uri/ $uri.html /index.html;
    }

    access_log /var/log/nginx/<domain>.access.log main;
    error_log  /var/log/nginx/<domain>.error.log warn;
}
```

---

## 8. PHP-FPM per-site pool template

One pool per site gives you per-site user isolation, per-site slow logs, and independent sizing. Save as `/etc/php/8.3/fpm/pool.d/<site>.conf`.

```ini
[<site>]
user  = www-data
group = www-data

; Unix socket is faster than TCP on the same host
listen = /run/php/<site>.sock
listen.owner = www-data
listen.group = www-data
listen.mode  = 0660

; Dynamic process manager
pm = dynamic
pm.max_children      = 20        ; hard cap
pm.start_servers     = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 8
pm.max_requests      = 500       ; recycle worker after N requests (bounds leaks)
pm.process_idle_timeout = 10s

; Slow log — anything above 5s gets a PHP stack trace
slowlog = /var/log/php/<site>.slow.log
request_slowlog_timeout = 5s

; Per-pool access log (comment out in production if noise is too high)
access.log = /var/log/php/<site>.access.log
access.format = "%R - %u %t \"%m %r%Q%q\" %s %f %{mili}d %{kilo}M %C%%"

; Catch worker stderr into the php-fpm error log
catch_workers_output = yes

; Per-site PHP overrides (override what the site needs; leave php.ini defaults alone)
php_admin_value[memory_limit]     = 256M
php_admin_value[upload_max_filesize] = 64M
php_admin_value[post_max_size]    = 64M
php_admin_value[max_execution_time] = 60
php_admin_value[error_log]        = /var/log/php/<site>.error.log
php_admin_flag[log_errors]        = on
php_admin_value[date.timezone]    = Africa/Nairobi
php_admin_value[session.save_path] = /var/lib/php/sessions/<site>
```

Prepare the log and session dirs:

```bash
sudo mkdir -p /var/log/php /var/lib/php/sessions/<site>
sudo chown www-data:www-data /var/log/php /var/lib/php/sessions/<site>
sudo chmod 700 /var/lib/php/sessions/<site>

sudo php-fpm8.3 -t
sudo systemctl reload php8.3-fpm
```

---

## 9. Apache vhost on port 8080 (PHP backend)

Every PHP backend vhost must listen **only** on `127.0.0.1:8080`. Nothing should hit Apache directly from the Internet — UFW plus the `127.0.0.1` bind address enforce this.

File: `/etc/apache2/sites-available/<domain>.conf`

```apache
<VirtualHost 127.0.0.1:8080>
    ServerName <domain>
    ServerAlias www.<domain>
    DocumentRoot /var/www/html/<folder>

    <Directory /var/www/html/<folder>>
        Options -Indexes +FollowSymLinks
        AllowOverride All                # required for .htaccess rewrites
        Require all granted
    </Directory>

    # Trust X-Forwarded-* only from Nginx (loopback)
    RemoteIPHeader      X-Forwarded-For
    RemoteIPInternalProxy 127.0.0.1

    # Log to per-site files
    ErrorLog  ${APACHE_LOG_DIR}/<domain>-error.log
    CustomLog ${APACHE_LOG_DIR}/<domain>-access.log combined

    # Hide server signature (defence in depth — Nginx already does this)
    ServerSignature Off

    # Deny dotfile access at Apache layer too
    <FilesMatch "^\.">
        Require all denied
    </FilesMatch>
    <FilesMatch "\.(env|git|sql|bak|htpasswd|htaccess|log|ini)$">
        Require all denied
    </FilesMatch>
</VirtualHost>
```

Enable:

```bash
sudo a2ensite <domain>.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

The first time you set up Apache on 8080, also confirm `/etc/apache2/ports.conf` contains **only** `Listen 127.0.0.1:8080`:

```apache
# /etc/apache2/ports.conf
Listen 127.0.0.1:8080
```

Verify:

```bash
sudo ss -tlnp | grep apache    # expect: 127.0.0.1:8080
```

---

## 10. Node.js systemd unit template

File: `/etc/systemd/system/<service-name>.service`

```ini
[Unit]
Description=<App Name> API
Documentation=https://<domain>/docs
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/var/www/html/<folder>
EnvironmentFile=/etc/<service-name>.env
ExecStart=/usr/bin/node dist/server.js
Restart=on-failure
RestartSec=5
KillSignal=SIGINT
TimeoutStopSec=20
StandardOutput=journal
StandardError=journal
SyslogIdentifier=<service-name>

# Resource limits
LimitNOFILE=65535
MemoryMax=512M

# Hardening — sandbox the Node process
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictRealtime=true
ReadWritePaths=/var/www/html/<folder>/logs /var/www/html/<folder>/uploads

[Install]
WantedBy=multi-user.target
```

Companion environment file `/etc/<service-name>.env` (root:root, 0600):

```bash
NODE_ENV=production
PORT=3001
DATABASE_URL=postgres://user:pass@127.0.0.1:5432/dbname
JWT_SECRET=<random-64-bytes>
LOG_LEVEL=info
```

Enable and start:

```bash
sudo chmod 600 /etc/<service-name>.env
sudo systemctl daemon-reload
sudo systemctl enable --now <service-name>
sudo systemctl status <service-name>
sudo journalctl -u <service-name> -n 50 --no-pager
```

---

## 11. Catch-all server (reject unknown hostnames)

Install in `/etc/nginx/sites-available/00-default.conf` and symlink. This prevents the first defined vhost from accidentally serving traffic for unknown `Host:` headers (which is how IP-scanners and preview certificates leak data).

```nginx
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;

    # Snakeoil cert — ships with `ssl-cert` package, regenerate with
    # `sudo make-ssl-cert generate-default-snakeoil --force-overwrite`
    ssl_certificate     /etc/ssl/certs/ssl-cert-snakeoil.pem;
    ssl_certificate_key /etc/ssl/private/ssl-cert-snakeoil.key;

    server_name _;
    return 444;                            # drop connection without response
}
```

---

## 12. Sources

- Atef, Ghada. *Mastering Ubuntu: A Comprehensive Guide to Linux's Favorite.* 2023 — Chapter V (System Administration), Chapter VI (Ubuntu for Servers), sections on managing services, networking, and web server installation.
- Canonical. *Ubuntu Server Guide — Linux 20.04 LTS (Focal).* 2020 — Web servers (Apache, Nginx), PHP, databases, and service management chapters.
- `man 5 nginx.conf`, `man 8 php-fpm8.3`, `man 5 apache2.conf` on Ubuntu 22.04/24.04.
- Upstream defaults in `/etc/nginx/nginx.conf`, `/etc/php/8.3/fpm/pool.d/www.conf`, `/etc/apache2/apache2.conf` as shipped by the Debian/Ubuntu packaging.
