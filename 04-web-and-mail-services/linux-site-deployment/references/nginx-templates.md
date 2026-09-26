# Nginx & Apache Vhost Templates

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

These Nginx server-block examples cover Astro/static, PHP direct via PHP-FPM, PHP via Apache on port 8080, Astro+PHP hybrid, and Node.js reverse-proxy patterns. They contain placeholders and version/path assumptions; they are not copy-paste-ready or a complete TLS profile. Code blocks that use `sudo` illustrate possible actions, not authority to run them. Follow [`../SKILL.md`](../SKILL.md) for approval and rollback. The Apache-on-8080 backend template appears at the end with shared snippets.

Contents: shared snippets, patterns A?E, Apache backend, certificate review, and sources.

---

## 1. Pre-requisite snippets

Every template below references snippet files. Confirm the target Nginx prefix and configured include paths, then prepare the reviewed snippets there; `/etc/nginx/snippets/` is an example, not a universal package default. Missing includes fail `nginx -t`.

### 1.1 `ssl-params.conf`

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
# Cipher-suite policy is intentionally not prescribed by this shared template.
# Select and verify it for the target Nginx/OpenSSL package and client scope.
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_session_tickets off;
# OCSP stapling is also target-specific. Enable only after configuring the
# trusted certificate chain and an approved resolver, then verify the response.
# ssl_stapling on;
# ssl_stapling_verify on;
# ssl_trusted_certificate <verified-ca-chain>;
# resolver <approved-resolver-addresses> valid=300s;
# resolver_timeout 5s;
```

### 1.2 `security-headers.conf`

```nginx
# Enable HSTS only after external HTTPS passes; start with a short host-only policy.
# `includeSubDomains` covers all subdomains (RFC 6797); require all to be HTTPS-ready
# and get domain-owner approval. Do not add `preload` by default.
# add_header Strict-Transport-Security "max-age=300" always;
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

### 1.5 `fastcgi-php.conf` (Ubuntu-style example)

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

### 1.8 Nginx HTTP/2 version selection

Check version/module with `nginx -v`/`-V`. Nginx 1.25.1+ uses
`listen 443 ssl;` plus `http2 on;`; older versions add `http2` to both listen
lines and omit `http2 on;`. If unavailable, omit HTTP/2. The old parameter is
deprecated; RHEL 9 documents 1.20/1.22. Run `nginx -t` before activation.

---

The following vhost file paths use the Ubuntu package layout as an example.
Place each server block under the host's actual included configuration path;
the directives do not create or enable a vhost by themselves.

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
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
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
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
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
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
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
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
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
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
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

## 8. Certificate installation and configuration review

Certbot's Nginx plugin can install certificates; treat it as a privileged
config change. Preserve the file, obtain authority, review the diff, run
`nginx -t`, and verify external health. Use
[`linux-firewall-ssl`](../../../07-security-and-hardening/linux-firewall-ssl/SKILL.md)
for certificate and renewal steps.

```bash
sudo certbot --nginx -d <domain>
sudo nginx -t
sudo systemctl reload nginx
```

Test renewal behavior without saving a certificate:

```bash
sudo certbot renew --dry-run
```

---

## 9. Sources

Current references checked 2026-09-26: NGINX [HTTP/2](https://nginx.org/en/docs/http/ngx_http_v2_module.html), [`listen`](https://nginx.org/en/docs/http/ngx_http_core_module.html), [headers](https://nginx.org/en/docs/http/ngx_http_headers_module.html), [SSL](https://nginx.org/en/docs/http/ngx_http_ssl_module.html); [RFC 6797](https://www.rfc-editor.org/info/rfc6797/); [RHEL 9 web guide](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html-single/deploying_web_servers_and_reverse_proxies/index); [Certbot CLI](https://eff-certbot.readthedocs.io/en/stable/man/certbot.html).

The legacy cipher list was removed without a replacement: target-specific
cipher selection and OCSP stapling remain **NOT_ASSESSED** until checked against
the chosen Nginx/OpenSSL packages and client requirements. These examples are
not a complete TLS profile.
