# Certbot Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Certbot is the reference ACME client for Let's Encrypt and most other public
ACME CAs. On Ubuntu/Debian it is the shortest path from "I have a domain" to
"I have a trusted TLS certificate that renews itself". This reference covers
installation, challenge types, issuance, renewal, wildcards, debugging, and
the rate limits you will hit if you script it carelessly.

## Table of contents

- [Installation — apt vs snap](#installation--apt-vs-snap)
- [Anatomy of /etc/letsencrypt/](#anatomy-of-etcletsencrypt)
- [ACME challenge types](#acme-challenge-types)
- [Issuing certificates](#issuing-certificates)
- [The nginx and apache plugins](#the-nginx-and-apache-plugins)
- [Standalone and webroot](#standalone-and-webroot)
- [Manual mode](#manual-mode)
- [Wildcards via DNS-01](#wildcards-via-dns-01)
- [DNS plugins (Cloudflare, Route 53, others)](#dns-plugins-cloudflare-route-53-others)
- [Expanding an existing certificate](#expanding-an-existing-certificate)
- [ECDSA keys and --key-type](#ecdsa-keys-and---key-type)
- [Revoking and deleting certificates](#revoking-and-deleting-certificates)
- [Renewal — automatic and manual](#renewal--automatic-and-manual)
- [certbot.timer and deploy hooks](#certbottimer-and-deploy-hooks)
- [Rate limits you need to know](#rate-limits-you-need-to-know)
- [Staging environment (test, test, test)](#staging-environment-test-test-test)
- [Debugging renewal failures](#debugging-renewal-failures)
- [Multi-server / load-balanced deployments](#multi-server--load-balanced-deployments)
- [Sources](#sources)

## Installation — apt vs snap

Two supported paths:

**Apt (Ubuntu package).** Simple. The version follows the distro and lags
upstream by several minor releases:

```bash
sudo apt update
sudo apt install certbot python3-certbot-nginx python3-certbot-apache
```

**Snap (recommended by EFF).** Latest upstream, auto-updating core certbot
bits, and the only way to install certain DNS plugins without pip:

```bash
sudo snap install core
sudo snap refresh core
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/local/bin/certbot
```

You can only have one certbot on a box. If you are migrating from apt to
snap:

```bash
sudo apt-get remove certbot python3-certbot-nginx python3-certbot-apache
sudo snap install --classic certbot
sudo ln -sf /snap/bin/certbot /usr/local/bin/certbot
sudo certbot --version
```

New installs: **prefer snap**. It gets security fixes faster and makes DNS
plugins easier to keep current.

## Anatomy of /etc/letsencrypt/

```
/etc/letsencrypt/
├── accounts/              # ACME account keys (one per CA per environment)
├── archive/
│   └── example.com/
│       ├── cert1.pem      # leaf only
│       ├── chain1.pem     # intermediate(s)
│       ├── fullchain1.pem # leaf + intermediate(s)
│       └── privkey1.pem
├── live/
│   └── example.com/       # symlinks to the latest cert in archive/
│       ├── cert.pem   -> ../../archive/example.com/cert1.pem
│       ├── chain.pem  -> ../../archive/example.com/chain1.pem
│       ├── fullchain.pem -> ../../archive/example.com/fullchain1.pem
│       └── privkey.pem -> ../../archive/example.com/privkey1.pem
├── renewal/
│   └── example.com.conf   # authenticator, installer, deploy-hook for this cert
└── renewal-hooks/
    ├── pre/
    ├── deploy/
    └── post/
```

**Always reference `live/<name>/` in web server config**, never `archive/`.
The `live` symlinks are what certbot updates when it renews.

`archive/` is keyed by version number; it is useful for rolling back if a
renewal goes wrong — every previous key and cert is still there.

## ACME challenge types

The ACME protocol lets a CA verify you control the domain with one of three
challenges:

### HTTP-01

Certbot serves a token at:

```
http://<domain>/.well-known/acme-challenge/<token>
```

The CA fetches that URL over plain HTTP. It must return exactly the
expected body.

- **Port 80 must be reachable from the public internet.** If port 80 is
  firewalled, HTTP-01 cannot work.
- **Follows up to ~10 redirects.** You can redirect port 80 to port 443
  **except** for `/.well-known/acme-challenge/` which must stay on 80 (or
  redirect to HTTPS as long as the TLS cert is valid).
- **Does not support wildcards.**
- Simplest, default, works for almost everyone.

### DNS-01

Certbot creates a TXT record:

```
_acme-challenge.<domain>  IN  TXT  "<token>"
```

The CA resolves that name over DNS. No web server required.

- **Only option for wildcards** (`*.example.com`).
- Works for **private hosts** (no port 80 needed).
- Requires API access to your DNS provider, or manual entry.
- Slower propagation (must wait for DNS).

### TLS-ALPN-01

The CA opens a TLS connection to port 443 and uses an ALPN protocol name
`acme-tls/1`. Certbot responds with a one-off self-signed cert containing
the token.

- **Port 443 must be reachable**; port 80 is not used.
- Useful on IPv6-only hosts where port 80 is blocked.
- No wildcards.
- Supported by the `certbot` standalone authenticator
  (`--preferred-challenges tls-alpn-01`).

## Issuing certificates

Every certbot issuance combines two plugins:

- **Authenticator** — proves domain control (nginx, apache, webroot,
  standalone, manual, dns-*).
- **Installer** — edits web server config to use the new cert (nginx,
  apache, or nothing).

Shortcut forms:

```bash
# Authenticate + install with the nginx plugin in one shot:
sudo certbot --nginx -d example.com -d www.example.com

# Authenticate + install with apache:
sudo certbot --apache -d example.com

# Authenticate with webroot (no installer):
sudo certbot certonly --webroot -w /var/www/html -d example.com

# Authenticate with standalone certbot HTTP server (nothing else on :80):
sudo systemctl stop nginx
sudo certbot certonly --standalone -d example.com
sudo systemctl start nginx
```

Subcommands:

- `certbot run` (or just `certbot`) — authenticate and install.
- `certbot certonly` — authenticate only; do not touch server config.
- `certbot install` — install an already-issued cert.
- `certbot renew` — renew any cert due within 30 days.
- `certbot certificates` — list all certs and their expiry.
- `certbot revoke` — revoke a cert.
- `certbot delete` — forget about a cert.
- `certbot update_account` — change the registered email.

Common flags:

| Flag | Meaning |
|---|---|
| `-d example.com` | domain name (may repeat) |
| `-n` | non-interactive |
| `--agree-tos` | agree to the ACME subscriber agreement |
| `-m you@example.com` | registration email (expiry alerts go here) |
| `--no-eff-email` | decline the EFF mailing list prompt |
| `--dry-run` | run against staging without creating a real cert |
| `--force-renewal` | renew even if more than 30 days remain |
| `--expand` | add new names to an existing cert |
| `--cert-name NAME` | lineage name (file path under `live/`) |
| `--preferred-challenges TYPE` | pick http, dns, tls-alpn-01 |
| `--key-type ecdsa` | issue ECDSA instead of RSA |
| `--elliptic-curve secp384r1` | curve when `--key-type ecdsa` |
| `--deploy-hook CMD` | run CMD after a successful renewal |

## The nginx and apache plugins

These are the magic path. Certbot parses the web server config, adds a
`server` or `<VirtualHost>` block for HTTPS, references the new cert, and
reloads.

```bash
sudo certbot --nginx -d example.com -d www.example.com \
  --agree-tos -m admin@example.com --no-eff-email -n
```

Certbot will:

1. Find a `server` block listening on 80 for `example.com`.
2. Ask the CA for a challenge token.
3. Add a temporary location `/.well-known/acme-challenge/...` and reload.
4. CA fetches the token → success.
5. Write a new `server` block on 443 with `ssl_certificate` pointing to
   `/etc/letsencrypt/live/example.com/fullchain.pem`.
6. Offer to redirect HTTP to HTTPS (pick `2` = redirect).
7. Reload nginx again.

The apache plugin works the same way but edits `<VirtualHost>`.

After certbot edits your config, re-check it reflects your intended
hardening (HSTS header, protocol list, etc.). Certbot does the minimum
needed to work — it is not a hardening tool.

## Standalone and webroot

**Standalone.** Certbot listens on port 80 itself. Use this only if nothing
else is bound there:

```bash
sudo systemctl stop nginx
sudo certbot certonly --standalone -d example.com
sudo systemctl start nginx
```

Fine for a first-time bootstrap on a brand-new server where nginx is not
yet configured. Unattractive for renewals because it requires stopping the
web server.

**Webroot.** Certbot writes the challenge file into a directory served by
your existing web server:

```bash
sudo certbot certonly --webroot -w /var/www/html -d example.com -d www.example.com
```

Nginx must serve `/.well-known/acme-challenge/` from `/var/www/html/` for
both names. This is the cleanest authenticator when you do not want certbot
touching your config. It renews without disruption. Every HTTP vhost needs:

```nginx
location /.well-known/acme-challenge/ {
    root /var/www/html;
}
```

Audit that all HTTP vhosts have the block:

```bash
sudo grep -rL "acme-challenge" /etc/nginx/sites-enabled/ | xargs -I{} echo "missing: {}"
```

## Manual mode

For one-off certs where automation is impossible. You paste a DNS record or
HTTP file by hand:

```bash
sudo certbot certonly --manual --preferred-challenges dns -d example.com
```

Certbot prints the record to add; create it; press Enter. Do **not** use
`--manual` in scripts — it cannot renew automatically unless you also
provide `--manual-auth-hook` and `--manual-cleanup-hook` scripts.

## Wildcards via DNS-01

Only DNS-01 can prove control of `*.example.com`. You will need a DNS
plugin (see next section) or manual mode.

With a DNS plugin (example: Cloudflare):

```bash
sudo certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /root/.secrets/cloudflare.ini \
  -d example.com -d "*.example.com" \
  --preferred-challenges dns
```

The resulting cert is a single lineage `example.com` in
`/etc/letsencrypt/live/example.com/` valid for both the apex and any
subdomain.

## DNS plugins (Cloudflare, Route 53, others)

Install a DNS plugin matching your provider:

```bash
# Snap certbot:
sudo snap set certbot trust-plugin-with-root=ok
sudo snap install certbot-dns-cloudflare
sudo snap install certbot-dns-route53
sudo snap install certbot-dns-digitalocean
sudo snap install certbot-dns-google

# Apt certbot:
sudo apt install python3-certbot-dns-cloudflare
sudo apt install python3-certbot-dns-route53
sudo apt install python3-certbot-dns-digitalocean
sudo apt install python3-certbot-dns-google
```

Each plugin needs credentials. Cloudflare uses a scoped API token:

```bash
sudo mkdir -p /root/.secrets
sudo tee /root/.secrets/cloudflare.ini >/dev/null <<'EOF'
# Cloudflare API token (Zone:DNS:Edit for example.com)
dns_cloudflare_api_token = <TOKEN>
EOF
sudo chmod 600 /root/.secrets/cloudflare.ini
```

Then issue:

```bash
sudo certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /root/.secrets/cloudflare.ini \
  -d example.com -d '*.example.com' \
  -m admin@example.com --agree-tos -n
```

Route 53 uses IAM (attach a policy that permits
`route53:ChangeResourceRecordSets` on the hosted zone). DigitalOcean,
Google Cloud DNS, and AWS use their own credential files.

**Propagation delay.** Some providers need 30–120 seconds before the TXT
record is visible to Let's Encrypt's resolvers. Add
`--dns-cloudflare-propagation-seconds 60` if you see intermittent
`NXDOMAIN` errors during validation.

## Expanding an existing certificate

Adding `api.example.com` to an existing `example.com` cert:

```bash
sudo certbot certonly --nginx --expand \
  -d example.com -d www.example.com -d api.example.com
```

`--expand` rewrites the cert lineage in place. You must list **every**
name, old and new — the names you omit are dropped.

Check the result:

```bash
sudo certbot certificates
# Certificate Name: example.com
#   Domains: example.com www.example.com api.example.com
#   Expiry Date: 2025-06-12 01:14:37+00:00 (VALID: 89 days)
```

## ECDSA keys and --key-type

By default certbot issues RSA 2048. Force ECDSA for new certs:

```bash
sudo certbot --nginx -d example.com \
  --key-type ecdsa --elliptic-curve secp384r1
```

To flip an existing RSA cert to ECDSA without changing the lineage name,
force a renewal with the new key type:

```bash
sudo certbot renew --cert-name example.com \
  --key-type ecdsa --elliptic-curve secp384r1 \
  --force-renewal
```

Let's Encrypt supports ECDSA with curves `secp256r1` and `secp384r1`.
Some legacy embedded clients only understand RSA — test before flipping a
business-critical cert.

## Revoking and deleting certificates

```bash
# Revoke (tells the CA: do not trust this cert anymore):
sudo certbot revoke --cert-path /etc/letsencrypt/live/example.com/cert.pem

# Revocation reasons (RFC 5280):
sudo certbot revoke --cert-path ... --reason keycompromise

# After revoke, also delete the local lineage so it does not try to renew:
sudo certbot delete --cert-name example.com
```

Revocation uses your stored account key for authentication. If the account
is gone (e.g. you reinstalled from scratch), you can revoke by uploading
the private key itself (`--key-path`).

Delete **without** revocation when you simply no longer need the cert:

```bash
sudo certbot delete --cert-name example.com
```

This removes the files under `live/` and `renewal/` but leaves `archive/`
for audit.

## Renewal — automatic and manual

```bash
# Test — runs all renewals against the staging environment:
sudo certbot renew --dry-run

# Real renewal (only renews certs within 30 days of expiry):
sudo certbot renew

# Force even if weeks remain — use sparingly (rate limit risk):
sudo certbot renew --force-renewal

# Renew only one lineage:
sudo certbot renew --cert-name example.com
```

Renewal is **idempotent**. Run it as often as you like in a cron or
systemd timer — it will only actually contact the CA when a cert is within
30 days of expiry. Let's Encrypt issues 90-day certs, so the renewal
window opens at day 60.

## certbot.timer and deploy hooks

Both the apt and snap packages install a systemd timer that runs
`certbot renew` twice a day at random times:

```bash
systemctl list-timers 'certbot*'
# NEXT                         LEFT     LAST                    PASSED UNIT
# Mon 2025-03-24 04:12:53 UTC  7h left  Sun 2025-03-23 16:25:11  4h ago certbot.timer

systemctl cat certbot.timer
# [Timer]
# OnCalendar=*-*-* 00,12:00:00
# RandomizedDelaySec=43200
```

Do nothing else. If you see both a `cron.d/certbot` entry **and** the timer
active, remove one — double-renewal is pointless.

**Deploy hooks** run after each successful renewal. Use them to reload web
servers or rsync certs to other nodes. Two ways to configure:

1. Drop a script into `/etc/letsencrypt/renewal-hooks/deploy/`:

```bash
sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-services.sh >/dev/null <<'EOF'
#!/bin/sh
systemctl reload nginx
systemctl reload apache2 2>/dev/null || true
systemctl reload postfix 2>/dev/null || true
systemctl reload dovecot 2>/dev/null || true
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-services.sh
```

Every cert inherits this hook automatically.

2. Per-cert hook in `/etc/letsencrypt/renewal/example.com.conf`:

```ini
renew_hook = systemctl reload nginx
```

Or pass it at first issuance:

```bash
sudo certbot --nginx -d example.com \
  --deploy-hook "systemctl reload nginx"
```

`renewal-hooks/pre/` runs before validation (stop a service), `post/` runs
after, `deploy/` runs only if a new cert was actually issued.

## Rate limits you need to know

Let's Encrypt enforces several rate limits. The ones that bite:

| Limit | Value | Reset window |
|---|---|---|
| Certs per registered domain | **50 per week** | rolling 7 days |
| Duplicate certificate | **5 per week** | rolling 7 days |
| Failed validation | **5 failures per account per hostname per hour** | 1 hour |
| Pending authorizations | 300 per account | — |
| New orders | 300 per account per 3 hours | — |
| Accounts per IP | 50 per 3 hours | — |

"Duplicate certificate" means the same exact set of names. Iterating on a
config change will run you into this quickly. **Use the staging environment
(`--test-cert`) until the config is working**, then issue once against prod.

An exemption form exists for high-volume hosting, but you should not need
it on a normal fleet. See <https://letsencrypt.org/docs/rate-limits/>.

## Staging environment (test, test, test)

Let's Encrypt provides a parallel staging CA that issues certs from a
throwaway root (browsers will reject them) but has **no meaningful rate
limits**. Use it obsessively.

```bash
# Dry run — uses staging under the hood, no file written:
sudo certbot renew --dry-run

# Real staging cert (files written to /etc/letsencrypt/, but untrusted):
sudo certbot --nginx -d example.com --test-cert

# Clean up staging cert before requesting the real one:
sudo certbot delete --cert-name example.com
sudo certbot --nginx -d example.com     # real cert
```

Always `--dry-run` after:

- changing DNS
- adding or removing a domain
- upgrading certbot
- moving between apt and snap
- editing `/etc/letsencrypt/renewal/*.conf`

## Debugging renewal failures

Symptom: renewal email says "certificate expires in 7 days".

```bash
# 1. See what certbot thinks:
sudo certbot certificates
sudo certbot renew --dry-run
sudo journalctl -u certbot --no-pager | tail -50
sudo journalctl -u certbot.timer --no-pager | tail -20

# 2. Reproduce with verbose output:
sudo certbot renew --dry-run -v --debug 2>&1 | tee /tmp/renew-debug.log

# 3. Check the renewal config file has what you expect:
sudo cat /etc/letsencrypt/renewal/example.com.conf
```

Common causes:

**Port 80 not reachable (HTTP-01).**

```bash
# From an external machine:
curl -I http://example.com/.well-known/acme-challenge/test
# must return 404, not connection refused / timeout
```

Open 80 in UFW **and** in the cloud provider security group. Certbot
cannot work if port 80 is blocked.

**Web server missing the acme-challenge location.**

```bash
sudo grep -rL "acme-challenge" /etc/nginx/sites-enabled/
```

Fix by adding the location block to every HTTP vhost.

**DNS record stale.** Moved servers? Check:

```bash
dig +short example.com A
dig +short example.com AAAA
```

**Plugin mismatch after OS upgrade.**

```bash
sudo certbot --version
# If you upgraded Ubuntu but certbot is still the old apt version, remove
# and reinstall (snap is the easiest).
```

**Certbot can renew but deploy hook fails.** The new cert is on disk but
nginx is still serving the old one. Test hook:

```bash
sudo /etc/letsencrypt/renewal-hooks/deploy/reload-services.sh
sudo journalctl -u nginx -n 20
```

**Account key problem.**

```bash
sudo ls /etc/letsencrypt/accounts/
# Should contain one directory per environment
```

If the account key is missing, you cannot renew — you must re-register:

```bash
sudo certbot register -m admin@example.com --agree-tos --no-eff-email
```

## Multi-server / load-balanced deployments

Two servers behind a load balancer both need the same cert. Options:

1. **Issue on one node, rsync to the others** via the deploy hook:

```bash
sudo tee /etc/letsencrypt/renewal-hooks/deploy/sync-to-peers.sh >/dev/null <<'EOF'
#!/bin/sh
for peer in web2.internal web3.internal; do
  rsync -a --delete /etc/letsencrypt/live/ root@$peer:/etc/letsencrypt/live/
  rsync -a --delete /etc/letsencrypt/archive/ root@$peer:/etc/letsencrypt/archive/
  ssh root@$peer 'systemctl reload nginx'
done
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/sync-to-peers.sh
```

Requires passwordless SSH as root to peers (lock down with
`from="10.0.0.5"` in `authorized_keys`).

2. **DNS-01 on a central box** that does not serve traffic, then distribute
   files out of band. Useful when none of the web nodes have port 80 open
   to the internet (e.g. behind an AWS ALB that already terminates TLS).

3. **Centralise in a shared filesystem or secret store** (Vault, AWS Secrets
   Manager). Each web node reads from the store at reload time. Most
   robust, most plumbing.

Whichever path you pick, test the full cycle in staging before a real
90-day cert is on the line.

## Sources

- Canonical, *Ubuntu Server Guide* (20.04 LTS), certificate and
  Let's Encrypt sections.
- Ghada Atef, *Mastering Ubuntu* (2023), web server security chapter.
- EFF Certbot documentation — <https://eff-certbot.readthedocs.io>.
- Let's Encrypt documentation — <https://letsencrypt.org/docs/>.
- Let's Encrypt rate limits — <https://letsencrypt.org/docs/rate-limits/>.
- ACME protocol: RFC 8555.
- Certbot DNS plugins — <https://certbot.eff.org/docs/using.html#dns-plugins>.
