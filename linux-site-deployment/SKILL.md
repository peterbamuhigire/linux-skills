---
name: linux-site-deployment
description: Deploy a new website to a Linux server running Nginx + Apache dual-stack, across both the Debian/Ubuntu and RHEL families (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). Interactive — asks domain name and site type (Astro static / PHP app / Astro+PHP hybrid), generates the correct Nginx config, walks the full 8-step deployment, issues SSL, and registers the repo in update-all-repos. Vhost enablement differs (a2ensite symlink on Debian/Ubuntu vs dropping *.conf in conf.d on RHEL), the web user differs (www-data vs apache), and deploying under SELinux on RHEL requires labeling the docroot (httpd_sys_content_t).
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Site Deployment

## Distro support

Two-family skill. Static/PHP/Node deployment is largely portable; the
differences are how an Apache vhost is enabled, the web-server user, the
firewall, and — on the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma,
Oracle) — **SELinux labeling of the docroot**.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Enable Apache vhost | `a2ensite` (symlink) + reload | drop `*.conf` in `/etc/httpd/conf.d/` + reload |
| Web server user:group | `www-data:www-data` | `apache:apache` |
| Default docroot | `/var/www/html` | `/var/www/html` (same) |
| Reload web server | `systemctl reload apache2` / `nginx` | `systemctl reload httpd` / `nginx` |
| Open firewall | `ufw allow 80,443/tcp` | `firewall-cmd --permanent --add-service={http,https}; --reload` |
| **Docroot under SELinux** | n/a | label `httpd_sys_content_t` + `restorecon`; uploads `httpd_sys_rw_content_t` |

**RHEL deploy gotcha:** after copying a site into a custom docroot, set the
SELinux context or it serves 403s despite correct unix permissions:
`sudo semanage fcontext -a -t httpd_sys_content_t "/var/www/example(/.*)?" && sudo restorecon -Rv /var/www/example`.
See [`../linux-webstack/references/httpd-reference.md`](../linux-webstack/references/httpd-reference.md)
and [`../linux-server-hardening/references/selinux-reference.md`](../linux-server-hardening/references/selinux-reference.md).
In `sk-*` scripts use `svc_name`, `web_conf_dir`, `web_reload`, `firewall_allow`
from `common.sh`. Plan: [`docs/multi-distro/plan.md`](../docs/multi-distro/plan.md).

## Use when

- Deploying a new website to the standard Nginx plus Apache server model in this repo.
- Adding a static site, PHP app, or Astro/PHP hybrid to an existing host.
- Issuing TLS and registering the repo in the repo-update workflow as part of deployment.

## Do not use when

- The server itself is not yet provisioned; use `linux-server-provisioning`.
- The task is generic web stack debugging rather than a new deployment; use `linux-webstack`.

## Required inputs

- The domain name.
- The site type and repo location.
- Any build, Apache backend, or deployment-path details needed for the chosen site model.

## Workflow

1. Collect deployment inputs up front: domain, site type, repo, and build needs.
2. Follow the eight deployment steps in order.
3. Validate web server config and TLS before making the site live.
4. Verify the final site response and repo registration state after deployment.

## Quality standards

- Deployment should leave the site reachable, renewable, and maintainable.
- Nginx validation and repo-registration steps are mandatory.
- Final verification must prove both HTTP behavior and operational update path.

## Anti-patterns

- Skipping `nginx -t` before reload.
- Deploying a site without registering its repo in the update workflow.
- Treating certificate issuance as optional for a production deployment.

## Outputs

- A deployed site with the correct vhost pattern.
- The config, TLS, and repo-registration actions taken.
- Verification that the site resolves and serves as expected.

## References

- [`references/deployment-checklist.md`](references/deployment-checklist.md)
- [`references/nginx-templates.md`](references/nginx-templates.md)
- [`references/apache-backend.md`](references/apache-backend.md)
- [`../linux-webstack/references/httpd-reference.md`](../linux-webstack/references/httpd-reference.md) — httpd conf.d model (RHEL family)
- [`../linux-server-hardening/references/selinux-reference.md`](../linux-server-hardening/references/selinux-reference.md) — SELinux docroot labeling (RHEL family)

This skill is self-contained. Every step below works with only the tools
that ship with the Debian/Ubuntu and RHEL families (see Distro support above
for the per-family command differences). The `sk-*` scripts listed in the Scripts
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

**Local work is preserved.** `update-all-repos` uses
`git pull --rebase --autostash` and a `git status --porcelain` dirty-check; it
never runs `git reset --hard` or `git clean -fd`. Uncommitted edits are
stashed and re-applied, untracked files are left in place. On a rebase
conflict it stops and reports the recovery path rather than discarding work.
See the `linux-repo-sync` skill for the binding doctrine.

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
| sk-update-all-repos | scripts/sk-update-all-repos.sh | yes | Pull all registered repos on this server; interactive menu + `--all`/`--repo` flags. |
| sk-nginx-new-site | scripts/sk-nginx-new-site.sh | no | Generate a new Nginx vhost from template, issue cert via certbot, reload. |
| sk-apache-new-site | scripts/sk-apache-new-site.sh | no | Generate an Apache vhost on port 8080, `a2ensite`, `configtest`, reload. |
| sk-astro-deploy | scripts/sk-astro-deploy.sh | no | Clone an Astro site, install deps, build, set up Nginx vhost + SSL, register in `update-all-repos`. |
| sk-php-site-deploy | scripts/sk-php-site-deploy.sh | no | Clone a PHP site, set ownership, configure vhost, SSL, register in `update-all-repos`. |
| sk-static-site-deploy | scripts/sk-static-site-deploy.sh | no | Clone a static site, configure vhost, SSL, register in `update-all-repos`. |
