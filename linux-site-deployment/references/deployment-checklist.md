# Site Deployment Checklist

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

An ordered, end-to-end checklist for deploying a new site to an Ubuntu/Debian server running the Nginx + Apache + PHP-FPM dual stack. Every step includes the exact command to run, the expected result, and what to do if it fails. The 8-step sequence is followed by a post-deploy verification block and a tested rollback procedure — so a bad deploy can be undone in under two minutes without leaving the server in a broken state.

## Table of contents

1. Pre-flight checks
2. The 8 deployment steps
3. Post-deploy verification
4. Rollback procedure
5. Sources

---

## 1. Pre-flight checks

Before you touch the server, confirm the following. Skipping any one of these turns into an emergency 30 minutes later.

```bash
# DNS A record points at the server's public IP
dig +short <domain>
dig +short www.<domain>
# Expect: the server's public IPv4

# Server has DNS for the ACME challenge
curl -s https://acme-v02.api.letsencrypt.org/directory | head

# Enough disk space for the clone + build
df -h /var/www/html /var/log /var
# Expect: > 500 MB free everywhere

# Nginx and Apache both running and healthy
systemctl is-active nginx apache2 php8.3-fpm
# Expect: active, active, active

# Existing sites test-pass
sudo nginx -t
sudo apache2ctl configtest
```

If DNS is wrong, **stop**. Fix DNS first — waiting for propagation is faster than fighting a cert that can't validate.

---

## 2. The 8 deployment steps

### Step 1 — Clone

```bash
cd /var/www/html
sudo git clone <repo-url> <folder>
sudo chown -R www-data:www-data /var/www/html/<folder>
```

**Expected output:** `Cloning into '<folder>'... done.`

**If it fails:**
- `fatal: unable to access ... 403`: the repo is private — add an SSH deploy key or use a PAT in the URL.
- `Permission denied (publickey)`: server has no SSH key for the git host.
- `No space left on device`: clean up `/var/www` before retrying.

### Step 2 — Build (Patterns A and E only)

```bash
cd /var/www/html/<folder>
sudo -u www-data npm install --production
sudo -u www-data npm run build
# For hybrid (Astro + PHP):
sudo -u www-data composer install --no-dev --optimize-autoloader
```

**Expected output:** A `dist/` directory containing `index.html` and asset files.

**If it fails:**
- `npm ERR! peer dep missing`: check Node version (`node --version`) — some projects need Node 20 LTS.
- Out-of-memory kill during `npm run build`: temporarily add swap or run the build locally and rsync the `dist/` directory up.
- `composer install` asking for auth: the composer.lock references a private package — add credentials to `~www-data/.composer/auth.json`.

### Step 3 — Create the Nginx vhost

```bash
sudo nano /etc/nginx/sites-available/<domain>.conf
```

Paste the correct template from `references/nginx-templates.md`:
- Pattern A — Astro / pure static
- Pattern B — PHP direct via PHP-FPM
- Pattern C — PHP via Apache 8080
- Pattern D — Astro + PHP hybrid
- Pattern E — Node.js reverse-proxy

Replace every `<domain>` and `<folder>` placeholder. Save and exit.

### Step 4 — Enable the site

```bash
sudo ln -s /etc/nginx/sites-available/<domain>.conf /etc/nginx/sites-enabled/
ls -la /etc/nginx/sites-enabled/<domain>.conf
# Expect: symlink → /etc/nginx/sites-available/<domain>.conf
```

**If the symlink already exists:** you're re-deploying; remove and re-create with `sudo rm` first.

### Step 5 — Test and reload Nginx

```bash
sudo nginx -t
```

**Expected output:**
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

**If it fails:**
- `unknown directive`: typo in the vhost file.
- `host not found in upstream`: an `upstream` block references a name that doesn't resolve — fix the upstream host.
- `could not build server_names_hash`: raise `server_names_hash_bucket_size` in `nginx.conf`.
- `duplicate listen options`: another vhost already claims `default_server` on the same port — drop the duplicate.

Once `nginx -t` passes:

```bash
sudo systemctl reload nginx
```

**Expected:** command returns without output. A failed reload will log to `journalctl -u nginx`.

Smoke-test the HTTP (not HTTPS) vhost before issuing certs:

```bash
curl -sI -H "Host: <domain>" http://127.0.0.1/
# Expect: HTTP/1.1 301 Moved Permanently + Location: https://<domain>/
```

### Step 6 — Issue SSL via certbot

```bash
sudo certbot --nginx -d <domain> -d www.<domain>
```

Certbot will:
1. Ask for an email (first run only).
2. Ask you to agree to the ToS.
3. Validate via HTTP-01 on port 80.
4. Rewrite the vhost to add `ssl_certificate` / `ssl_certificate_key`.
5. Reload Nginx.

**Expected output:** `Successfully received certificate.` and `Deploying certificate` for each domain.

**If it fails:**
- `Challenge failed for domain <domain>`: DNS isn't pointing here yet, or UFW is blocking port 80, or the `acme-challenge.conf` snippet isn't included in the HTTP server block. Check with `curl http://<domain>/.well-known/acme-challenge/test`.
- `Too many certificates already issued`: hit the Let's Encrypt rate limit — use `--staging` to iterate, then switch back once the config is stable.
- `The server experienced an internal error`: check `/var/log/letsencrypt/letsencrypt.log`.

Verify the cert is installed and loads:

```bash
sudo certbot certificates | grep -A4 "<domain>"
curl -sI https://<domain>/ | head
# Expect: HTTP/2 200 (or a valid redirect)
```

### Step 7 — Apache vhost (Patterns C and D only)

```bash
sudo nano /etc/apache2/sites-available/<domain>.conf
```

Paste the Apache template from `references/apache-backend.md`. Replace `<domain>` and `<folder>`.

```bash
sudo a2ensite <domain>.conf
sudo apache2ctl configtest
sudo systemctl reload apache2
```

Smoke-test Apache directly on loopback:

```bash
curl -sI -H "Host: <domain>" http://127.0.0.1:8080/
# Expect: HTTP/1.1 200 OK (or the app's expected redirect)
```

Then test the full public path:

```bash
curl -sI https://<domain>/
# Expect: HTTP/2 200
```

**If the Nginx→Apache proxy returns 502:**
- Is Apache running? `sudo systemctl status apache2`.
- Is Apache bound to 127.0.0.1:8080? `sudo ss -tlnp | grep apache2`.
- Is the vhost enabled? `sudo a2query -s <domain>.conf`.
- Tail the logs in parallel: `sudo tail -f /var/log/nginx/<domain>.error.log /var/log/apache2/<domain>-error.log`.

### Step 8 — Register in update-all-repos

```bash
sudo nano /usr/local/bin/update-all-repos
```

Add a line for the new site in the REPOS array. Example entry format:

```bash
"Example Site|/var/www/html/example|npm install --production && npm run build"
```

Build commands by pattern:
- **A** (Astro / static): `npm install --production && npm run build`
- **B** (PHP direct): *(leave empty)*
- **C** (PHP via Apache): *(leave empty)*
- **D** (Astro + PHP hybrid): `composer install --no-dev --optimize-autoloader && npm install --production && npm run build`
- **E** (Node.js API): `npm install --production && npm run build && sudo systemctl restart <service-name>`

**WARNING:** `update-all-repos` runs `git reset --hard` before pulling. Any uncommitted server-side changes in the repo will be destroyed. Commit and push anything you want kept before running it.

Per `~/.claude/skills/notes/new-repo-checklist.md`, this step is **not optional** — if the repo is not in `update-all-repos` it will silently stop getting updates.

---

## 3. Post-deploy verification

Run every check below. All must pass before announcing the site as live.

### 3.1 HTTP status

```bash
curl -sI https://<domain>/ | grep -E "HTTP/|Server:"
# Expect: HTTP/2 200   (or HTTP/2 301 if the app redirects)

curl -sI https://www.<domain>/ | grep -E "HTTP/|Server:"
# Expect: HTTP/2 200 or HTTP/2 301 to apex
```

### 3.2 Certificate is valid

```bash
sudo certbot certificates | grep -A4 "<domain>"
# Expect: VALID: 89 days (or similar), key type: ECDSA/RSA

echo | openssl s_client -servername <domain> -connect <domain>:443 2>/dev/null | openssl x509 -noout -dates
# Expect: notAfter = ~90 days from now
```

### 3.3 Nginx logs clean

```bash
sudo journalctl -u nginx -n 50 --no-pager | tail -30
sudo tail -20 /var/log/nginx/<domain>.error.log
# Expect: no recent errors at warn/crit level
```

### 3.4 PHP-FPM pool running (Pattern B, C, D)

```bash
sudo systemctl is-active php8.3-fpm
# Expect: active

# Per-site pool socket exists
ls -la /run/php/<site>.sock 2>/dev/null || ls -la /run/php/php8.3-fpm.sock
# Expect: srw-rw---- www-data www-data
```

### 3.5 update-all-repos pulls successfully

```bash
sudo /usr/local/bin/update-all-repos <site-number>
# Expect: "Already up to date." or a successful pull + rebuild
```

### 3.6 UFW isn't blocking

```bash
sudo ufw status verbose | grep -E '80|443'
# Expect: 80/tcp ALLOW, 443/tcp ALLOW; 8080 must NOT appear
```

### 3.7 Permissions correct

```bash
stat -c '%U:%G %a %n' /var/www/html/<folder>
find /var/www/html/<folder> -type d -exec stat -c '%U:%G %a %n' {} \; | head
# Expect: owner www-data:www-data, dirs 755, files 644
```

Fix if wrong:

```bash
sudo chown -R www-data:www-data /var/www/html/<folder>
sudo find /var/www/html/<folder> -type d -exec chmod 755 {} \;
sudo find /var/www/html/<folder> -type f -exec chmod 644 {} \;
```

### 3.8 No world-writable files in webroot

```bash
sudo find /var/www/html/<folder> -type f -perm -o+w
# Expect: (no output)
```

If any appear, strip the bit:

```bash
sudo find /var/www/html/<folder> -type f -perm -o+w -exec chmod o-w {} \;
```

### 3.9 Secrets not in git

```bash
cd /var/www/html/<folder>
git ls-files | grep -Ei '\.(env|pem|key|sql)$' && echo "LEAK" || echo "clean"
# Expect: clean
```

### 3.10 Certbot auto-renewal works

```bash
sudo systemctl status certbot.timer
sudo certbot renew --dry-run
# Expect: "Congratulations, all renewals succeeded" and the timer is active
```

---

## 4. Rollback procedure

If any step fails and the site is now broken, follow this order. Each phase is a clean undo of the step before; you can stop wherever things work again.

### Phase 1 — Disable the new Nginx vhost

```bash
sudo rm /etc/nginx/sites-enabled/<domain>.conf
sudo nginx -t && sudo systemctl reload nginx
```

The site now returns from the catch-all (444 / closed) or the previous vhost if one existed. Other sites on the box are unaffected.

### Phase 2 — Disable the Apache vhost (if Pattern C/D)

```bash
sudo a2dissite <domain>.conf
sudo apache2ctl configtest && sudo systemctl reload apache2
```

### Phase 3 — Revoke the certificate (only if you issued it in this session)

```bash
sudo certbot delete --cert-name <domain>
```

**Only do this** if you're abandoning the deployment entirely. Otherwise, leave the cert — it doesn't hurt anything and will be reused on the next attempt.

### Phase 4 — Remove the clone

```bash
sudo rm -rf /var/www/html/<folder>
```

### Phase 5 — Remove from update-all-repos

```bash
sudo nano /usr/local/bin/update-all-repos
# Delete the entry for this site
```

### Phase 6 — Re-verify other sites

After every rollback, confirm unrelated sites still work:

```bash
for site in site1.com site2.com; do
    code=$(curl -s -o /dev/null -w '%{http_code}' https://$site/)
    echo "$site → $code"
done
```

Any non-200 means the rollback damaged something — check `sudo nginx -t`, `sudo apache2ctl configtest`, and `journalctl -u nginx -u apache2 -n 50`.

---

## 5. Sources

- Atef, Ghada. *Mastering Ubuntu: A Comprehensive Guide to Linux's Favorite.* 2023 — Chapter V (System Administration) and Chapter VI (Ubuntu for Servers).
- Canonical. *Ubuntu Server Guide — Linux 20.04 LTS (Focal).* 2020 — web servers, TLS, and systemd chapters.
- Let's Encrypt / certbot documentation at <https://eff-certbot.readthedocs.io/>.
- `man 8 certbot`, `man 8 a2ensite`, `man 8 nginx` on Ubuntu 22.04/24.04.
