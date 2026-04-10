# Nginx & Apache Vhost Templates

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Full copy-pasteable Nginx vhost templates for every deployment pattern handled by the `linux-site-deployment` skill: Astro/static, PHP direct via PHP-FPM, PHP via Apache on port 8080, Astro+PHP hybrid, and Node.js reverse-proxy. Each template survives `certbot --nginx --expand` cleanly (certbot inserts the SSL directives without clobbering the rest), includes the HTTP-to-HTTPS redirect with the ACME challenge exemption, modern TLS, security headers, long-lived cache headers for static assets, and error pages. The Apache-on-8080 backend template used by patterns B and C appears at the end, together with the snippet library every template references.

## Table of contents

1. Pre-requisite snippets
2. Pattern A — Astro / pure static site
3. Pattern B — PHP direct via PHP-FPM socket
4. Pattern C — PHP via Apache 8080
5. Pattern D — Astro + PHP hybrid
6. Pattern E — Node.js reverse-proxy
7. Apache backend vhost template (port 8080)
8. What certbot adds (and how to survive it)
9. Sources

---

## 1. Pre-requisite snippets

Every template below expects these files in `/etc/nginx/snippets/`. If any are missing, the `include` lines error out in `nginx -t`. Install all snippets once on a new server — the provisioning skill does this in Section 9.

### 1.1 `ssl-params.conf`

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

### 1.2 `security-headers.conf`

```nginx
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Content-Type-Options    "nosniff" always;
add_header X-Frame-Options           "SAMEORIGIN" always;
add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
add_header Permissions-Policy        "camera=(), microphone=(), geolocation=(), interest-cohort=()" always;
add_header X-XSS-Protection          "0" always;
```

### 1.3 `security-dotfiles.conf`

```nginx
location ~ /\.(?!well-known) { deny all; return 404; }
location ~* \.(env|git|sql|bak|backup|old|orig|swp|htpasswd|htaccess|ini|yaml|yml|lock|dist)$ { deny all; return 404; }
```

### 1.4 `static-files.conf`

```nginx
location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp|avif|woff|woff2|ttf|eot|otf)$ {
    expires 1y;
    add_header Cache-Control "public, immutable" always;
    access_log off;
    try_files $uri =404;
}
```

### 1.5 `fastcgi-php.conf`

```nginx
fastcgi_pass unix:/run/php/php8.3-fpm.sock;
fastcgi_index index.php;
fastcgi_split_path_info ^(.+\.php)(/.+)$;
fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
fastcgi_param PATH_INFO $fastcgi_path_info;
fastcgi_param HTTPS $https if_not_empty;
include fastcgi_params;
fastcgi_read_timeout 60s;
fastcgi_intercept_errors on;
```

### 1.6 `proxy-to-apache.conf`

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
```

### 1.7 `acme-challenge.conf`

```nginx
location ^~ /.well-known/acme-challenge/ {
    default_type "text/plain";
    root /var/www/html;
    allow all;
}
```

---

## 2. Pattern A — Astro / pure static site

Astro builds to `dist/`; Nginx serves the files directly, no PHP or Node involved. Works for any static generator (11ty, Hugo, Jekyll, plain HTML).

File: `/etc/nginx/sites-available/<domain>.conf`

```nginx
# --- HTTP → HTTPS redirect ---
server {
    listen 80;
    listen [::]:80;
    server_name <domain> www.<domain>;

    include snippets/acme-challenge.conf;
    location / { return 301 https://$host$request_uri; }
}

# --- HTTPS ---
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name <domain> www.<domain>;

    root /var/www/html/<folder>/dist;
    index index.html;

    # Certbot inserts ssl_certificate / ssl_certificate_key here
    include snippets/ssl-params.conf;
    include snippets/security-headers.conf;
    include snippets/security-dotfiles.conf;
    include snippets/static-files.conf;

    # Astro file-based routes: /about → /about.html
    location / {
        try_files $uri $uri/ $uri.html /index.html;
    }

    # Custom 404 (if dist/404.html exists)
    error_page 404 /404.html;
    location = /404.html { internal; }

    access_log /var/log/nginx/<domain>.access.log;
    error_log  /var/log/nginx/<domain>.error.log warn;
}
```

---

## 3. Pattern B — PHP direct via PHP-FPM socket

Use for plain PHP, WordPress, Laravel, or Symfony where you don't need Apache's `.htaccess` layer. Faster than going through Apache.

File: `/etc/nginx/sites-available/<domain>.conf`

```nginx
# --- HTTP → HTTPS redirect ---
server {
    listen 80;
    listen [::]:80;
    server_name <domain> www.<domain>;

    include snippets/acme-challenge.conf;
    location / { return 301 https://$host$request_uri; }
}

# --- HTTPS ---
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name <domain> www.<domain>;

    root /var/www/html/<folder>/public;   # /public for Laravel/Symfony; webroot for WordPress
    index index.php index.html;

    include snippets/ssl-params.conf;
    include snippets/security-headers.conf;
    include snippets/security-dotfiles.conf;
    include snippets/static-files.conf;

    client_max_body_size 64M;

    # Front controller — route everything through index.php
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    # Execute PHP via FPM
    location ~ \.php$ {
        try_files $uri =404;                 # refuse requests for non-existent .php
        include snippets/fastcgi-php.conf;
        # Per-site pool (comment out to use the default www pool):
        fastcgi_pass unix:/run/php/<site>.sock;
    }

    # Never execute PHP inside upload dirs (defence against file-upload RCE)
    location ~* /(uploads|files|media|cache)/.*\.php$ {
        deny all;
        return 404;
    }

    error_page 404 /index.php;
    error_page 500 502 503 504 /50x.html;
    location = /50x.html { root /var/www/html/errors; internal; }

    access_log /var/log/nginx/<domain>.access.log;
    error_log  /var/log/nginx/<domain>.error.log warn;
}
```

---

## 4. Pattern C — PHP via Apache 8080

Use when the app depends on `.htaccess` rewrites, legacy Apache-specific modules, or shared hosting behaviour. Nginx handles TLS, static assets and headers; Apache handles PHP execution.

File: `/etc/nginx/sites-available/<domain>.conf`

```nginx
# --- HTTP → HTTPS redirect ---
server {
    listen 80;
    listen [::]:80;
    server_name <domain> www.<domain>;

    include snippets/acme-challenge.conf;
    location / { return 301 https://$host$request_uri; }
}

# --- HTTPS ---
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name <domain> www.<domain>;

    root /var/www/html/<folder>;
    index index.php index.html;

    include snippets/ssl-params.conf;
    include snippets/security-headers.conf;
    include snippets/security-dotfiles.conf;

    client_max_body_size 64M;

    # Serve static assets straight from Nginx — faster than proxying
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|webp|avif|woff|woff2|ttf|eot)$ {
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

    # PHP files go to Apache (never let Nginx touch them in this pattern)
    location ~ \.php$ {
        include snippets/proxy-to-apache.conf;
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html { root /var/www/html/errors; internal; }

    access_log /var/log/nginx/<domain>.access.log;
    error_log  /var/log/nginx/<domain>.error.log warn;
}
```

---

## 5. Pattern D — Astro + PHP hybrid

Static marketing pages from Astro build, PHP API under `/api/`. The PHP API can be served either via PHP-FPM directly (edit the `location /api/` block to include `fastcgi-php.conf`) or via Apache on 8080 (the default below).

File: `/etc/nginx/sites-available/<domain>.conf`

```nginx
# --- HTTP → HTTPS redirect ---
server {
    listen 80;
    listen [::]:80;
    server_name <domain> www.<domain>;

    include snippets/acme-challenge.conf;
    location / { return 301 https://$host$request_uri; }
}

# --- HTTPS ---
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name <domain> www.<domain>;

    root /var/www/html/<folder>/dist;
    index index.html;

    include snippets/ssl-params.conf;
    include snippets/security-headers.conf;
    include snippets/security-dotfiles.conf;
    include snippets/static-files.conf;

    # PHP API backend (proxied to Apache on 8080)
    location /api/ {
        include snippets/proxy-to-apache.conf;
    }

    # Block any .php request outside /api/ — /dist should never contain PHP
    location ~ ^/(?!api/).*\.php$ {
        deny all;
        return 404;
    }

    # Static front end
    location / {
        try_files $uri $uri/ $uri.html /index.html;
    }

    error_page 404 /404.html;

    access_log /var/log/nginx/<domain>.access.log;
    error_log  /var/log/nginx/<domain>.error.log warn;
}
```

---

## 6. Pattern E — Node.js reverse-proxy

Use for a Node.js API (Express, Fastify, NestJS) or any long-running HTTP service that listens on a loopback port. The systemd unit lives in `linux-webstack` (`references/config-patterns.md`).

File: `/etc/nginx/sites-available/<domain>.conf`

```nginx
upstream <service>_upstream {
    server 127.0.0.1:3001;
    keepalive 32;
}

# --- HTTP → HTTPS redirect ---
server {
    listen 80;
    listen [::]:80;
    server_name <domain>;

    include snippets/acme-challenge.conf;
    location / { return 301 https://$host$request_uri; }
}

# --- HTTPS ---
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name <domain>;

    include snippets/ssl-params.conf;
    include snippets/security-headers.conf;

    client_max_body_size 16M;

    # WebSocket upgrade path (if the app uses them)
    location /ws {
        proxy_pass http://<service>_upstream;
        proxy_http_version 1.1;
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host       $host;
        proxy_read_timeout 3600s;
    }

    # Main proxy
    location / {
        proxy_pass http://<service>_upstream;
        proxy_http_version 1.1;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection        "";          # reuse upstream keepalive
        proxy_connect_timeout 5s;
        proxy_read_timeout    60s;
        proxy_send_timeout    60s;
        proxy_buffering       off;                      # stream responses
    }

    access_log /var/log/nginx/<domain>.access.log;
    error_log  /var/log/nginx/<domain>.error.log warn;
}
```

---

## 7. Apache backend vhost template (port 8080)

Required by Patterns C and D. Apache listens **only** on `127.0.0.1:8080` — never on a public address. Verify `/etc/apache2/ports.conf` contains only:

```apache
Listen 127.0.0.1:8080
```

File: `/etc/apache2/sites-available/<domain>.conf`

```apache
<VirtualHost 127.0.0.1:8080>
    ServerName <domain>
    ServerAlias www.<domain>
    DocumentRoot /var/www/html/<folder>

    <Directory /var/www/html/<folder>>
        Options -Indexes +FollowSymLinks
        AllowOverride All                  # allow .htaccess rewrites
        Require all granted
    </Directory>

    # Trust X-Forwarded-* only from loopback (Nginx)
    RemoteIPHeader        X-Forwarded-For
    RemoteIPInternalProxy 127.0.0.1

    # Deny dotfiles and secrets at Apache layer
    <FilesMatch "^\.">
        Require all denied
    </FilesMatch>
    <FilesMatch "\.(env|git|sql|bak|htpasswd|htaccess|log|ini|yml)$">
        Require all denied
    </FilesMatch>

    ServerSignature Off

    ErrorLog  ${APACHE_LOG_DIR}/<domain>-error.log
    CustomLog ${APACHE_LOG_DIR}/<domain>-access.log combined
</VirtualHost>
```

Enable and reload:

```bash
sudo a2ensite <domain>.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

---

## 8. What certbot adds (and how to survive it)

When you run `sudo certbot --nginx -d <domain> -d www.<domain>`, the nginx plugin rewrites your config by:

1. Adding `ssl_certificate` and `ssl_certificate_key` directives inside the `listen 443` server block.
2. Adding `include /etc/letsencrypt/options-ssl-nginx.conf;` and `ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;`.
3. Adding a managed-by-certbot comment block at the bottom.

To survive `certbot --nginx --expand` cleanly later:

- Keep your `server_name` line alphabetised and on one line — certbot parses it with a naive regex.
- Leave your `include snippets/ssl-params.conf` line in place; certbot's `options-ssl-nginx.conf` does not conflict with it (the later include wins on overlapping directives).
- Don't wrap the `listen 443 ssl http2;` block in an `if`. Certbot won't find it.
- After running certbot, diff the file and confirm nothing outside the SSL server block changed:

```bash
sudo certbot --nginx -d <domain>
sudo nginx -t
sudo systemctl reload nginx
```

Dry-run the renewal to be certain it will work unattended:

```bash
sudo certbot renew --dry-run
```

---

## 9. Sources

- Atef, Ghada. *Mastering Ubuntu: A Comprehensive Guide to Linux's Favorite.* 2023 — Chapter VI (Ubuntu for Servers), Apache and Nginx installation and configuration.
- Canonical. *Ubuntu Server Guide — Linux 20.04 LTS (Focal).* 2020 — Web servers (Apache, Nginx) and TLS chapters.
- Let's Encrypt / certbot documentation at <https://eff-certbot.readthedocs.io/> for the `--nginx` installer behaviour.
- Mozilla SSL Configuration Generator (intermediate profile) for the cipher list baseline.
