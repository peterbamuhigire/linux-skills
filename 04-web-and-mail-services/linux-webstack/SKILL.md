---
name: linux-webstack
description: Manage the web stack on Debian/Ubuntu AND RHEL-family servers (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) — Nginx reverse proxy (config, reload, debug 502), Apache backend (port 8080 vhosts), PHP-FPM (pool tuning, restart), and Node.js API services (systemd). Nginx is portable (conf.d on both); Apache differs the most — on RHEL it is `httpd` with a flat `/etc/httpd/conf.d/` model (no sites-available/a2ensite), PHP-FPM service and socket paths differ (`php-fpm` / `/etc/php-fpm.d/` / `/run/php-fpm/www.sock`), and SELinux governs web access on RHEL. Covers the Nginx+Apache dual-stack pattern where Nginx fronts all traffic and proxies PHP apps to Apache on port 8080.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Web Stack Management

## Distro support

Two-family skill. Nginx is portable (conf.d on both). **Apache differs the
most**: on the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle)
it is **`httpd`** with a flat **`/etc/httpd/conf.d/`** model — no
`sites-available`/`a2ensite`. And **SELinux** can block a correctly-permissioned
site. Full detail: [`references/httpd-reference.md`](references/httpd-reference.md).

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Apache package/service | `apache2` / `apache2ctl` | `httpd` / `apachectl` |
| Vhost model | `sites-available` + `a2ensite` | drop `*.conf` in `/etc/httpd/conf.d/` |
| Apache config root | `/etc/apache2/` | `/etc/httpd/` |
| Web run-as user | `www-data` | `apache` |
| Apache logs | `/var/log/apache2/` | `/var/log/httpd/` |
| PHP-FPM service / pool | `php8.x-fpm` / `/etc/php/8.x/fpm/pool.d/` | `php-fpm` / `/etc/php-fpm.d/` |
| PHP-FPM socket | `/run/php/php8.x-fpm.sock` | `/run/php-fpm/www.sock` |
| Newer PHP | Ondřej PPA | Remi repo / `dnf module` |
| MAC on web content | none | **SELinux**: `httpd_sys_content_t`, `httpd_can_network_connect` |

In `sk-*` scripts use `svc_name apache`, `web_conf_dir apache`, and
`web_reload apache` from `common.sh` instead of hardcoding. See
[`references/httpd-reference.md`](references/httpd-reference.md) and
[`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

## Use when

- Managing Nginx, Apache, PHP-FPM, or Node.js services in the standard web stack.
- Debugging reverse-proxy behavior, upstream failures, or PHP worker tuning.
- Validating config changes before reloading live web services.

## Do not use when

- The task is a brand-new site rollout; use `linux-site-deployment`.
- The task is certificate lifecycle or firewall policy; use `linux-firewall-ssl`.

## Required inputs

- The site, vhost, or service involved.
- Which layer is failing: Nginx, Apache, PHP-FPM, or Node.js.
- Any recent config or deployment changes that could explain the symptom.

## Workflow

1. Identify the failing web-stack layer and inspect its current config and status.
2. Apply the matching workflow below for reverse proxy, Apache backend, PHP-FPM, or Node.js.
3. Validate config before any reload or restart.
4. Confirm end-to-end request flow after the change.

## Quality standards

- Validate configs before reload every time.
- Keep responsibility boundaries clear across Nginx, Apache, PHP-FPM, and Node.js.
- Verify with real request behavior, not just successful daemon restarts.

## Anti-patterns

- Restarting multiple web services at once without isolating the failing layer.
- Editing configs without a validation step.
- Treating a 502 as only an Nginx problem when the upstream may be down or misconfigured.

## Outputs

- The web-stack diagnosis or change.
- The config tests and service checks performed.
- Confirmation of restored request flow or the next subsystem to inspect.

## References

- [`references/nginx-directives.md`](references/nginx-directives.md)
- [`references/config-patterns.md`](references/config-patterns.md)
- [`references/php-fpm-tuning.md`](references/php-fpm-tuning.md)
- [`references/httpd-reference.md`](references/httpd-reference.md) — Apache httpd + conf.d model + SELinux (RHEL family)

**This skill is self-contained.** Every command below is a standard tool on
both the Debian/Ubuntu and RHEL families (note the per-family naming in the
**Distro support** table above — e.g. `apache2ctl`/`apachectl`). The `sk-*`
scripts in the **Optional fast path** section are convenience wrappers — never
required.

```
Client → Nginx (443/80)
           ├── Astro/static → /dist/ folders
           ├── PHP direct → PHP-FPM socket
           ├── PHP apps → Apache (port 8080)
           └── Node.js APIs → localhost:<port>
```

---

## Nginx

```bash
sudo nginx -t                                      # test config (always first)
sudo nginx -t && sudo systemctl reload nginx       # graceful reload
sudo systemctl restart nginx                       # full restart

# Enable / disable site
sudo ln -s /etc/nginx/sites-available/<domain>.conf /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/<domain>.conf

sudo tail -f /var/log/nginx/error.log
sudo tail -f /var/log/nginx/access.log
```

### Debug 502 Bad Gateway

```bash
sudo tail -20 /var/log/nginx/error.log           # what upstream is failing?
sudo systemctl status php8.3-fpm                 # PHP-FPM sites
sudo systemctl status apache2                    # Apache-proxied sites
ls -la /run/php/php8.3-fpm.sock                  # FPM socket present?
sudo systemctl restart php8.3-fpm                # fix
```

Config patterns and templates: `references/config-patterns.md`

---

## Apache (Port 8080)

```bash
sudo apache2ctl configtest                        # test config
sudo apache2ctl configtest && sudo systemctl reload apache2
sudo a2ensite <domain>.conf
sudo a2dissite <domain>.conf
sudo tail -f /var/log/apache2/error.log
```

---

## PHP-FPM

```bash
sudo php-fpm8.3 -t                               # test config
sudo systemctl reload php8.3-fpm                # graceful
sudo systemctl restart php8.3-fpm               # full restart
sudo tail -f /var/log/php8.3-fpm.log
```

### Tune Workers

```bash
sudo nano /etc/php/8.3/fpm/pool.d/www.conf
# Key settings:
# pm.max_children = 20  (RAM-dependent: (RAM_MB - 256) / avg_worker_MB)
# pm.start_servers = 4
# pm.min_spare_servers = 2
# pm.max_spare_servers = 8
# pm.max_requests = 500
sudo systemctl reload php8.3-fpm
```

---

## Node.js Services

```bash
sudo systemctl status <service-name>
sudo journalctl -u <service-name> -n 50 --no-pager
sudo systemctl restart <service-name>
```

Create new Node.js systemd unit: see `references/config-patterns.md`.

---

## nginx.conf Global Settings

```bash
sudo nano /etc/nginx/nginx.conf
```
```nginx
worker_processes auto;
server_tokens off;         # hide version
client_max_body_size 64M;  # upload limit
gzip on;
```

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-webstack` installs wrappers for the
most common workflows:

| Task | Fast-path script |
|---|---|
| Validate + reload Nginx | `sudo sk-nginx-test-reload` |
| Validate + reload Apache | `sudo sk-apache-test-reload` |
| Generate a new PHP-FPM pool | `sudo sk-php-fpm-pool --site <domain>` |
| Analyze MySQL config | `sudo sk-mysql-tune` |
| Audit MySQL users & grants | `sudo sk-mysql-user-audit` |

These are optional convenience wrappers around the manual commands above.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-webstack
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-nginx-test-reload | scripts/sk-nginx-test-reload.sh | no | `nginx -t` then graceful reload; shows config summary and what changed since last reload. |
| sk-apache-test-reload | scripts/sk-apache-test-reload.sh | no | `apache2ctl configtest` then graceful reload. |
| sk-php-fpm-pool | scripts/sk-php-fpm-pool.sh | no | Generate a PHP-FPM pool for a site (socket, user, pm settings), enable, restart. |
| sk-mysql-tune | scripts/sk-mysql-tune.sh | no | Analyze `my.cnf` + runtime variables, suggest improvements. Non-destructive. |
| sk-mysql-user-audit | scripts/sk-mysql-user-audit.sh | no | Show MySQL users, hosts, grants; flag anonymous, `%` hosts, over-privileged users. |
