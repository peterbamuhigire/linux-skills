# Adding an Astro Site to This Server

Step-by-step guide for deploying a new Astro static site. Assumes the domain already points to this server via Namecheap DNS.

## 1. Clone the Repo

```bash
cd /var/www/html
sudo git clone git@github.com:YOUR_ORG/your-site.git your-site
sudo chown -R www-data:www-data your-site
```

## 2. Initial Build

```bash
cd /var/www/html/your-site
npm install --production
npm run build
```

This creates the `dist/` directory that Nginx will serve.

## 3. Create the Nginx Config

Create `/etc/nginx/sites-available/yourdomain.com.conf`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name yourdomain.com www.yourdomain.com;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name www.yourdomain.com;

    ssl_certificate     /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;
    include /etc/nginx/snippets/ssl-params.conf;

    return 301 https://yourdomain.com$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name yourdomain.com;

    ssl_certificate     /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;
    include /etc/nginx/snippets/ssl-params.conf;

    # Document root — serves from dist/
    root /var/www/html/your-site/dist;
    index index.html;

    # Root redirect (if site uses /en/ language prefix)
    # location = / {
    #     return 302 /en/;
    # }

    # Astro hashed assets — immutable cache
    location /_astro/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Images and fonts — 1 year
    location ~* \.(jpg|jpeg|png|gif|webp|avif|svg|ico|woff2|woff|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public";
        access_log off;
    }

    # CSS and JS — 1 month
    location ~* \.(css|js)$ {
        expires 30d;
        add_header Cache-Control "public";
        access_log off;
    }

    # HTML — no cache
    location ~* \.html$ {
        add_header Cache-Control "no-cache";
    }

    # Clean URLs
    location / {
        try_files $uri $uri/ $uri/index.html =404;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Deny hidden files
    location ~ /\. {
        deny all;
    }

    # Gzip
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript image/svg+xml font/woff2 font/woff application/font-woff2 application/font-woff;
    gzip_min_length 256;
}
```

**Naming convention:** `yourdomain.com.conf`

## 4. Enable the Site

```bash
sudo ln -s /etc/nginx/sites-available/yourdomain.com.conf /etc/nginx/sites-enabled/
```

## 5. Get SSL Certificate (Before Enabling HTTPS)

First, temporarily comment out the two `server` blocks that listen on 443 in your config (Certbot needs the port-80 block to work). Then:

```bash
sudo nginx -t && sudo systemctl reload nginx
sudo certbot certonly --webroot -w /var/www/html -d yourdomain.com -d www.yourdomain.com
```

Once the cert is issued, uncomment the 443 blocks and reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

**Alternative (let Certbot handle the config):**

```bash
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com
```

This automatically adds the SSL directives. Use this if you prefer Certbot-managed configs (see `techguypeter.com.conf` for an example of what this looks like).

## 6. Register in update-all-repos

**This is mandatory.** See `notes/new-repo-checklist.md` for full details.

```bash
sudo nano /usr/local/bin/update-all-repos
```

Add to the `REPO_LIST` array:

```bash
"Your Site (Astro)|/var/www/html/your-site|npm install --production && npm run build"
```

The third field (`npm install --production && npm run build`) is the post-update build step. It runs automatically when `git pull` detects changes.

## 7. Test & Verify

```bash
# Test nginx config
sudo nginx -t

# Reload
sudo systemctl reload nginx

# Test the site
curl -I https://yourdomain.com

# Test auto-update
update-repos   # select your new site from the menu
```

## Quick Reference

| Step | Command |
|------|---------|
| Clone | `git clone` into `/var/www/html/` |
| Build | `npm install --production && npm run build` |
| Nginx config | `/etc/nginx/sites-available/yourdomain.com.conf` |
| Enable site | `ln -s` to `sites-enabled/` |
| SSL cert | `certbot certonly --webroot` or `certbot --nginx` |
| Register repo | Add to `REPO_LIST` in `/usr/local/bin/update-all-repos` |
| SSL snippet | `/etc/nginx/snippets/ssl-params.conf` (shared TLS settings) |

## Notes

- All Astro sites serve from the `dist/` subdirectory, not the repo root
- The `ssl-params.conf` snippet handles TLS protocol/cipher settings — no need to repeat them per site
- Sites with i18n (language prefixes like `/en/`, `/fr/`) add a root `location = /` redirect to the default language
- Certbot auto-renews certs via a systemd timer — no manual renewal needed
