---
name: linux-site-deployment
description: Deploy a new website to an Ubuntu/Debian server running Nginx + Apache dual-stack. Interactive — asks domain name and site type (Astro static / PHP app / Astro+PHP hybrid), generates the correct Nginx config, walks the full 8-step deployment, issues SSL, and registers the repo in update-all-repos.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Site Deployment

This skill is self-contained. Every step below works with only the tools
that ship with Ubuntu/Debian. The `sk-*` scripts listed in the Scripts
manifest are an **optional fast path** that wraps the same steps — install
them if they make your life easier, but they are never required.

Ask these questions first:

1. **Domain name?** (e.g. example.com)
2. **Site type?**
   - **A** — Astro/static (Nginx serves `/dist/` directly)
   - **B** — PHP app (Nginx → Apache port 8080)
   - **C** — Astro + PHP hybrid (static front + PHP backend)
3. **Repo URL?**
4. **Node.js API needed?** (separate systemd service)

---

## The 8 Steps

### 1. Clone
```bash
cd /var/www/html   # or /var/www for some Astro sites
sudo git clone <repo-url> <folder-name>
```

### 2. Build (A and C only)
```bash
cd /var/www[/html]/<folder>
# Pattern A:  sudo npm install --production && sudo npm run build
# Pattern C:  sudo composer install --no-dev && sudo npm install --production && sudo npm run build
```

### 3. Create Nginx Config
```bash
sudo nano /etc/nginx/sites-available/<domain>.conf
```
See `references/nginx-templates.md` for the correct template per pattern.

### 4. Enable Site
```bash
sudo ln -s /etc/nginx/sites-available/<domain>.conf /etc/nginx/sites-enabled/
```

### 5. Test & Reload (mandatory)
```bash
sudo nginx -t && sudo systemctl reload nginx
# Fix any errors before continuing — never skip nginx -t
```

### 6. Issue SSL
```bash
sudo certbot --nginx -d <domain>
```

### 7. Apache Vhost (B and C only)
```bash
sudo nano /etc/apache2/sites-available/<domain>.conf
sudo a2ensite <domain>.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
```
See `references/nginx-templates.md` for the Apache vhost template.

### 8. Register in update-all-repos (mandatory)
```bash
sudo nano /usr/local/bin/update-all-repos
# Add entry: "Display Name|/path/to/repo|build command"
```

Per `~/.claude/skills/notes/new-repo-checklist.md` — this step is never optional.

**Build command by pattern:**
- A (Astro): `npm install --production && npm run build`
- B (PHP): *(leave empty)*
- C (Astro+PHP): `composer install --no-dev && npm install --production && npm run build`

**WARNING:** `update-all-repos` runs `git reset --hard`. Commit any server-side
changes to git before running it — they will be destroyed otherwise.

---

## Verify

```bash
curl -sI https://<domain> | grep -E "HTTP/|Server:"
sudo certbot certificates | grep -A3 "<domain>"
```

For Node.js API service setup, see `linux-webstack`.
Full Nginx/Apache config templates: `references/nginx-templates.md`

---

## Optional fast path (when sk-* scripts are installed)

If the `linux-site-deployment` scripts are installed
(`sudo install-skills-bin linux-site-deployment`), these one-liners run
the same 8 steps:

| Site type | Fast path |
|---|---|
| A — Astro / static | `sudo sk-astro-deploy --domain <d> --repo <url>` |
| A — static only | `sudo sk-static-site-deploy --domain <d> --repo <url>` |
| B — PHP | `sudo sk-php-site-deploy --domain <d> --repo <url>` |
| C — Astro + PHP hybrid | `sudo sk-astro-deploy --hybrid --domain <d> --repo <url>` |

Helper scripts for individual steps: `sk-nginx-new-site`,
`sk-apache-new-site`, `sk-nginx-test-reload`, `sk-apache-test-reload`,
`sk-cert-status`. All are optional wrappers around the manual commands
above.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-site-deployment
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-update-all-repos | scripts/update-all-repos | yes | Pull all registered repos on this server; interactive menu + `all`. (Legacy name kept for muscle memory.) |
| sk-nginx-new-site | scripts/sk-nginx-new-site.sh | no | Generate a new Nginx vhost from template, issue cert via certbot, reload. |
| sk-apache-new-site | scripts/sk-apache-new-site.sh | no | Generate an Apache vhost on port 8080, `a2ensite`, `configtest`, reload. |
| sk-astro-deploy | scripts/sk-astro-deploy.sh | no | Clone an Astro site, install deps, build, set up Nginx vhost + SSL, register in `update-all-repos`. |
| sk-php-site-deploy | scripts/sk-php-site-deploy.sh | no | Clone a PHP site, set ownership, configure vhost, SSL, register in `update-all-repos`. |
| sk-static-site-deploy | scripts/sk-static-site-deploy.sh | no | Clone a static site, configure vhost, SSL, register in `update-all-repos`. |
