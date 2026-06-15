# Apache httpd reference (RHEL family)

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

On the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) Apache is
packaged and run as **`httpd`**, not `apache2`, and it uses a **flat `conf.d/`
model** instead of Debian's `sites-available` + `sites-enabled` + `a2ensite`
workflow. This is the most disruptive web-stack difference between the families.

Use alongside [`config-patterns.md`](config-patterns.md),
[`nginx-directives.md`](nginx-directives.md), and
[`php-fpm-tuning.md`](php-fpm-tuning.md). In `sk-*` scripts, prefer the
`svc_name`, `web_conf_dir`, and `web_reload` helpers from `common.sh`.

---

## Apache: Debian vs RHEL

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Package | `apache2` | `httpd` |
| Service / binary | `apache2` / `apache2ctl` | `httpd` / `apachectl` |
| Main config | `/etc/apache2/apache2.conf` | `/etc/httpd/conf/httpd.conf` |
| Vhost dir | `/etc/apache2/sites-available/` → `sites-enabled/` | `/etc/httpd/conf.d/*.conf` (all loaded) |
| Enable a vhost | `a2ensite site.conf` (symlink) | **drop `.conf` in `conf.d/`** (no enable step) |
| Disable a vhost | `a2dissite site.conf` | move/rename the file out of `conf.d/` |
| Module config | `mods-available/` + `a2enmod` | `/etc/httpd/conf.modules.d/*.conf` |
| Enable a module | `a2enmod rewrite` | usually already loaded; else add a `LoadModule` line |
| Run-as user:group | `www-data:www-data` | `apache:apache` |
| Default docroot | `/var/www/html` | `/var/www/html` (same) |
| Config test | `apache2ctl configtest` | `apachectl configtest` (or `httpd -t`) |
| Logs | `/var/log/apache2/` | `/var/log/httpd/` |
| **MAC** | none by default | **SELinux enforced** (see below) |

**There is no `a2ensite`/`a2enmod` on RHEL.** A vhost is "enabled" simply by
existing as a `*.conf` file in `/etc/httpd/conf.d/`. To disable one, rename it
(e.g. `site.conf.disabled`) and reload.

---

## A portable vhost

The vhost *body* is identical; only the file location and reload differ.

```apache
# RHEL: /etc/httpd/conf.d/example.conf
# Debian: /etc/apache2/sites-available/example.conf  (then a2ensite)
<VirtualHost *:80>
    ServerName  example.com
    ServerAlias www.example.com
    DocumentRoot /var/www/example
    ErrorLog  /var/log/httpd/example_error.log      # apache2 on Debian
    CustomLog /var/log/httpd/example_access.log combined
    <Directory /var/www/example>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
```

```bash
# RHEL family
sudo apachectl configtest && sudo systemctl reload httpd
# Debian/Ubuntu
sudo a2ensite example.conf && sudo apache2ctl configtest && sudo systemctl reload apache2
```

---

## SELinux makes Apache behave differently on RHEL

On RHEL-family hosts, a vhost with correct file permissions can **still** fail
with 403s or connection errors purely because of SELinux. None of this exists
on Debian/Ubuntu. (Full detail:
[`../../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md).)

```bash
# 1. Content must be labeled httpd_sys_content_t (writable areas: _rw_content_t)
ls -Z /var/www/example
sudo semanage fcontext -a -t httpd_sys_content_t "/var/www/example(/.*)?"
sudo restorecon -Rv /var/www/example

# 2. PHP/Apache reaching a DB, API, or mail server needs a boolean
sudo setsebool -P httpd_can_network_connect on        # general outbound
sudo setsebool -P httpd_can_network_connect_db on     # DB specifically

# 3. Listening on a non-standard port needs the port labeled
sudo semanage port -a -t http_port_t -p tcp 8088
```

Symptom cheat-sheet:

- **403 on a path that has correct unix perms** → wrong file context →
  `restorecon`.
- **PHP "could not connect" to localhost DB/API** → `httpd_can_network_connect`.
- **httpd won't start on a custom port** → label the port `http_port_t`.
- Confirm the cause: `sudo ausearch -m AVC -ts recent | audit2why`.

---

## PHP-FPM differences

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Package | `php-fpm` (e.g. `php8.3-fpm`) | `php-fpm` |
| Service | `php8.3-fpm` | `php-fpm` |
| Pool dir | `/etc/php/8.3/fpm/pool.d/` | `/etc/php-fpm.d/` |
| Default socket | `/run/php/php8.3-fpm.sock` | `/run/php-fpm/www.sock` |
| Run-as user | `www-data` | `apache` |
| Newer PHP | deadsnakes / Ondřej PPA | **Remi** repo + `dnf module` streams |

```bash
# RHEL: select a PHP version stream, then install
sudo dnf module list php
sudo dnf module enable php:remi-8.3 -y      # Remi repo for current PHP
sudo dnf install -y php php-fpm php-mysqlnd
sudo systemctl enable --now php-fpm
```

When Apache/Nginx proxies to PHP-FPM over the socket, the socket path differs
(table above) **and** SELinux must allow it — usually covered by the stock
policy when using the default `/run/php-fpm/www.sock`.

---

## Firewall

Open the web ports with the family's firewall (see
[`../../../07-security-and-hardening/linux-firewall-ssl/references/firewalld-reference.md`](../../../07-security-and-hardening/linux-firewall-ssl/references/firewalld-reference.md)):

```bash
# RHEL family
sudo firewall-cmd --permanent --add-service=http --add-service=https
sudo firewall-cmd --reload
# Debian/Ubuntu
sudo ufw allow 80,443/tcp
```

---

## References

- [`config-patterns.md`](config-patterns.md) — shared web config patterns.
- [`nginx-directives.md`](nginx-directives.md) — Nginx (portable; conf.d on both).
- [`php-fpm-tuning.md`](php-fpm-tuning.md) — pool/process tuning (portable).
- [`../../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md`](../../../07-security-and-hardening/linux-server-hardening/references/selinux-reference.md) — SELinux for web.
- Man/docs: `httpd(8)`, `apachectl(8)`, Fedora "Setting up the Apache HTTP web server".
