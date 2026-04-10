# SSL/TLS Configuration Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This reference collects the full TLS/SSL configuration knowledge you need to
run a production HTTPS site on Ubuntu/Debian. It explains what each knob does,
gives copy-pasteable Nginx and Apache snippets, and walks through testing and
debugging certificates from the command line. The goal is a configuration that
scores A+ on SSL Labs, survives modern scanners, and renews itself without
ever breaking a site at 2 a.m.

## Table of contents

- [TLS 1.2 vs TLS 1.3 — what changed and why](#tls-12-vs-tls-13--what-changed-and-why)
- [Cipher suite selection (Mozilla profiles)](#cipher-suite-selection-mozilla-profiles)
- [ECDSA vs RSA certificates](#ecdsa-vs-rsa-certificates)
- [OCSP stapling](#ocsp-stapling)
- [HSTS (HTTP Strict Transport Security)](#hsts-http-strict-transport-security)
- [HPKP — deprecated (and why)](#hpkp--deprecated-and-why)
- [Diffie-Hellman parameters (ssl_dhparam)](#diffie-hellman-parameters-ssl_dhparam)
- [Session cache, tickets, and timeouts](#session-cache-tickets-and-timeouts)
- [Security headers to ship alongside TLS](#security-headers-to-ship-alongside-tls)
- [Production Nginx TLS snippet (full vhost)](#production-nginx-tls-snippet-full-vhost)
- [Production Apache mod_ssl snippet](#production-apache-mod_ssl-snippet)
- [Reusable snippets file](#reusable-snippets-file)
- [Inspecting live certificates with openssl](#inspecting-live-certificates-with-openssl)
- [Scanning with testssl.sh and sslscan](#scanning-with-testsslsh-and-sslscan)
- [SSL Labs / Mozilla Observatory](#ssl-labs--mozilla-observatory)
- [Common misconfigurations and how to detect them](#common-misconfigurations-and-how-to-detect-them)
- [Sources](#sources)

## TLS 1.2 vs TLS 1.3 — what changed and why

TLS 1.2 (RFC 5246, 2008) is the minimum acceptable protocol in 2024+.
TLS 1.0 and 1.1 were formally deprecated in RFC 8996 (March 2021) and must be
disabled. SSLv2 and SSLv3 (POODLE, 2014) are forbidden.

TLS 1.3 (RFC 8446, 2018) is a ground-up redesign:

- **One round-trip handshake** instead of two. Page load is noticeably faster
  on high-latency links, and 0-RTT resumption is possible (at the cost of
  replay safety — leave 0-RTT off unless you need it).
- **Forward secrecy is mandatory.** Only (EC)DHE key exchange is allowed. A
  stolen private key can no longer decrypt yesterday's traffic.
- **AEAD ciphers only.** All TLS 1.3 cipher suites use authenticated
  encryption (AES-GCM, ChaCha20-Poly1305). CBC, RC4, 3DES, MD5, SHA-1 are all
  gone.
- **Simpler cipher suite list.** TLS 1.3 ships with five suites; you do not
  pick them individually in Nginx — OpenSSL negotiates them automatically.
- **Encrypted handshake.** Certificates are sent under encryption, so
  on-path observers learn less about the connection.

A modern server should advertise exactly `TLSv1.2 TLSv1.3`. Drop 1.2 only if
you control every client (internal APIs, microservice mesh).

## Cipher suite selection (Mozilla profiles)

Mozilla publishes three reference profiles at
[ssl-config.mozilla.org](https://ssl-config.mozilla.org). Use one verbatim
rather than hand-rolling ciphers.

| Profile | Protocols | Browser floor | Use when |
|---|---|---|---|
| **Modern** | TLS 1.3 only | Firefox 63, Chrome 70, iOS 12.2 | Internal tools, admin panels, APIs you control |
| **Intermediate** | TLS 1.2 + 1.3 | Firefox 27, Chrome 31, IE 11 on Win 7 | Every public website |
| **Old** | TLS 1.0+ | IE 8 on XP | Never. Legal/regulatory forcing function only |

Intermediate is the default for public sites. Its Nginx cipher list (as of the
current generator output) is:

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;
```

Key points:

- **`ssl_prefer_server_ciphers off`** in Intermediate. With modern clients
  negotiating TLS 1.3 + AEAD, the client's preference order is fine; letting
  the client choose enables hardware-accelerated ChaCha20 on phones.
- **Forward secrecy everywhere.** Every suite begins with `ECDHE` or `DHE`.
- **ChaCha20-Poly1305** must come before AES if you want best performance on
  ARM devices without AES-NI.
- **No CBC, no RC4, no 3DES, no MD5, no SHA-1 signature algorithms.**

Modern profile (TLS 1.3 only) does not need `ssl_ciphers` at all — OpenSSL
picks from the built-in TLS 1.3 suites automatically.

## ECDSA vs RSA certificates

RSA-2048 is the historical default. ECDSA P-256 is a better choice in 2024:

| | RSA-2048 | ECDSA P-256 |
|---|---|---|
| Key size | 2048 bits | 256 bits |
| Signing speed | Slow | ~10× faster |
| Handshake CPU | Baseline | ~4× cheaper |
| TLS record size | Larger | Smaller |
| Browser support | 100 % | 100 % (all browsers since ~2013) |
| Quantum resistance | None | None (both broken by Shor's algorithm) |

Let's Encrypt supports ECDSA since Feb 2022. Force it when issuing:

```bash
sudo certbot --nginx -d example.com \
  --key-type ecdsa --elliptic-curve secp384r1
```

`secp256r1` (P-256) is also valid and slightly faster. `secp384r1` (P-384) is
what U.S. federal guidance (FIPS 186-5) prefers for long-lived assets.

Some very old clients (pre-2013 Android, old embedded devices) still require
RSA. If that matters, issue **both** certs with `--cert-name example-rsa` and
`--cert-name example-ecdsa` and configure Nginx to serve both:

```nginx
ssl_certificate     /etc/letsencrypt/live/example-ecdsa/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/example-ecdsa/privkey.pem;
ssl_certificate     /etc/letsencrypt/live/example-rsa/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/example-rsa/privkey.pem;
```

Nginx picks per client based on the `signature_algorithms` extension.

## OCSP stapling

When a browser validates a certificate it normally calls the CA's Online
Certificate Status Protocol (OCSP) responder to check whether the cert was
revoked. This leaks the visited site to the CA and adds latency.

**Stapling** fixes both: the web server periodically fetches the OCSP
response itself, caches it, and attaches ("staples") it to every TLS
handshake. The client trusts the staple because it is signed by the CA.

```nginx
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /etc/letsencrypt/live/example.com/chain.pem;
resolver 1.1.1.1 9.9.9.9 valid=300s;
resolver_timeout 5s;
```

- `ssl_trusted_certificate` must be the **issuer chain** (`chain.pem`), not
  the leaf cert. Certbot provides this file automatically.
- A `resolver` directive is required; Nginx needs DNS to reach the OCSP URL.
- Verify stapling is live:
  ```bash
  openssl s_client -connect example.com:443 -status </dev/null 2>&1 \
    | grep -A 17 "OCSP response"
  ```
  You should see `OCSP Response Status: successful (0x0)` and a
  `This Update` timestamp recent enough to be valid.

Let's Encrypt end-entity certs (post Sep 2024) set the
`OCSP Must-Staple` flag only if you pass `--must-staple` to certbot. Avoid
must-staple unless you are confident your stapling is rock-solid — a broken
staple hard-fails the connection.

## HSTS (HTTP Strict Transport Security)

HSTS tells browsers: "For the next N seconds, never connect to this host over
plain HTTP. If the certificate is invalid, do not let the user click
through." It defends against SSL-strip attacks on coffee-shop Wi-Fi.

```nginx
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
```

Parameters:

- **`max-age=63072000`** — two years in seconds. The minimum for the
  `preload` list. Start at `max-age=300` (5 minutes) while testing, then
  ramp up.
- **`includeSubDomains`** — the policy also applies to `*.example.com`.
  Only set this if every subdomain has TLS.
- **`preload`** — you are asking browsers to ship with this domain hard-coded
  as HTTPS-only. Submit at [hstspreload.org](https://hstspreload.org). Once
  preloaded, removal takes months.
- **`always`** is the Nginx keyword that forces the header to be sent even on
  4xx/5xx responses.

Serve HSTS **only** over HTTPS, never HTTP (the spec ignores it on HTTP
anyway, but sending it there is a red flag in scanners). The header above
belongs in the `443` server block.

## HPKP — deprecated (and why)

HTTP Public Key Pinning (RFC 7469, `Public-Key-Pins` header) let a site pin
the SHA-256 hash of one of its certificate public keys. Browsers would
refuse any future cert that did not match a pin.

Chrome removed HPKP in May 2018 (Chrome 67), Firefox followed. Reasons:

1. **Foot-gun.** A typo in the pin, or rotating to a new CA without including
   the old key hash, bricked the site for `max-age` days.
2. **RansomPKP.** Attackers who stole a private key could pin their own key
   and hold the site hostage.
3. **Very low adoption** — fewer than 0.1 % of HTTPS sites used it correctly.

**Do not set `Public-Key-Pins`.** Modern replacements:

- **Certificate Transparency** (RFC 6962) — every public cert must appear in
  a public log; rogue issuance is detectable.
- **DANE / TLSA** for DNSSEC-enabled zones.
- **HSTS preload** covers 95 % of what HPKP tried to solve.

## Diffie-Hellman parameters (ssl_dhparam)

DHE-RSA cipher suites need a DH group. If you do not configure one, Nginx
uses a weak 1024-bit default, vulnerable to the Logjam attack. Generate a
unique 2048-bit group once per server:

```bash
sudo openssl dhparam -out /etc/nginx/dhparam.pem 2048
```

```nginx
ssl_dhparam /etc/nginx/dhparam.pem;
```

Generation takes 1–10 minutes depending on CPU; it is safe to run in the
background. 4096-bit is overkill (Intermediate profile does not include any
DHE suite in TLS 1.2 if you stay with ECDHE-only, so `ssl_dhparam` becomes a
no-op — but the file costs nothing to keep).

## Session cache, tickets, and timeouts

Resuming a TLS session skips the asymmetric handshake. Two mechanisms:

1. **Session IDs** — server keeps the session state; client sends an ID.
2. **Session tickets** — server wraps state in an encrypted blob and sends
   it to the client, who stores it and returns it next time.

```nginx
ssl_session_cache shared:SSL:10m;   # 10 MB holds ~40 000 sessions
ssl_session_timeout 1d;             # resume window
ssl_session_tickets off;            # recommended: off
```

`ssl_session_tickets off` is the safer default. Ticket keys sit in RAM and
are rotated only on Nginx restart; an attacker who grabs the key can decrypt
previously captured handshakes, defeating forward secrecy. Behind a load
balancer with multiple Nginx nodes you need either a rotating shared ticket
key or tickets off — pick off.

TLS 1.3 has its own resumption mechanism (PSK-based), unaffected by these
directives.

## Security headers to ship alongside TLS

TLS is only half the story. Add these headers in every HTTPS vhost:

```nginx
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), camera=(), microphone=(), interest-cohort=()" always;
# Optional, CSP is app-specific:
# add_header Content-Security-Policy "default-src 'self'; img-src 'self' data: https:; script-src 'self'; style-src 'self' 'unsafe-inline'" always;
```

Test the resulting headers:

```bash
curl -sI https://example.com | grep -iE "strict-transport|x-frame|x-content|referrer|permissions|content-security"
```

## Production Nginx TLS snippet (full vhost)

Drop this into `/etc/nginx/sites-available/example.com.conf` and symlink it
into `sites-enabled/`. Replace `example.com` with your domain.

```nginx
# Redirect plain HTTP to HTTPS, except for ACME challenges.
server {
    listen      80;
    listen [::]:80;
    server_name example.com www.example.com;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen      443 ssl;
    listen [::]:443 ssl;
    http2       on;
    server_name example.com www.example.com;

    # Certificate (ECDSA preferred).
    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    # Mozilla Intermediate profile.
    ssl_protocols             TLSv1.2 TLSv1.3;
    ssl_ciphers               ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_dhparam               /etc/nginx/dhparam.pem;

    # Session handling.
    ssl_session_cache    shared:SSL:10m;
    ssl_session_timeout  1d;
    ssl_session_tickets  off;

    # OCSP stapling.
    ssl_stapling         on;
    ssl_stapling_verify  on;
    ssl_trusted_certificate /etc/letsencrypt/live/example.com/chain.pem;
    resolver             1.1.1.1 9.9.9.9 valid=300s;
    resolver_timeout     5s;

    # Security headers.
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options    "nosniff" always;
    add_header X-Frame-Options           "SAMEORIGIN" always;
    add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy        "geolocation=(), camera=(), microphone=()" always;

    root  /var/www/example.com;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    access_log /var/log/nginx/example.com.access.log;
    error_log  /var/log/nginx/example.com.error.log;
}
```

Validate, then reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

## Production Apache mod_ssl snippet

```apache
<VirtualHost *:80>
    ServerName example.com
    ServerAlias www.example.com

    # Keep ACME challenge on plain HTTP.
    Alias "/.well-known/acme-challenge/" "/var/www/html/.well-known/acme-challenge/"
    <Directory "/var/www/html/.well-known/acme-challenge/">
        Require all granted
    </Directory>

    RewriteEngine On
    RewriteCond %{REQUEST_URI} !^/\.well-known/acme-challenge/
    RewriteRule ^(.*)$ https://%{HTTP_HOST}$1 [R=301,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName example.com
    ServerAlias www.example.com
    DocumentRoot /var/www/example.com

    SSLEngine on
    SSLCertificateFile      /etc/letsencrypt/live/example.com/fullchain.pem
    SSLCertificateKeyFile   /etc/letsencrypt/live/example.com/privkey.pem

    # Mozilla Intermediate.
    SSLProtocol             -all +TLSv1.2 +TLSv1.3
    SSLCipherSuite          ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
    SSLHonorCipherOrder     off
    SSLSessionTickets       off

    SSLUseStapling          on
    SSLStaplingCache        "shmcb:${APACHE_LOG_DIR}/stapling-cache(150000)"

    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
    Header always set X-Content-Type-Options    "nosniff"
    Header always set X-Frame-Options           "SAMEORIGIN"
    Header always set Referrer-Policy           "strict-origin-when-cross-origin"

    ErrorLog  ${APACHE_LOG_DIR}/example.com-error.log
    CustomLog ${APACHE_LOG_DIR}/example.com-access.log combined
</VirtualHost>
```

```bash
sudo a2enmod ssl headers rewrite http2
sudo apache2ctl configtest && sudo systemctl reload apache2
```

## Reusable snippets file

Don't repeat the cipher/protocol/header block in every vhost. Save it once:

```bash
sudo mkdir -p /etc/nginx/snippets
sudo tee /etc/nginx/snippets/ssl-params.conf >/dev/null <<'EOF'
ssl_protocols             TLSv1.2 TLSv1.3;
ssl_ciphers               ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;
ssl_dhparam               /etc/nginx/dhparam.pem;
ssl_session_cache         shared:SSL:10m;
ssl_session_timeout       1d;
ssl_session_tickets       off;
ssl_stapling              on;
ssl_stapling_verify       on;
resolver                  1.1.1.1 9.9.9.9 valid=300s;
resolver_timeout          5s;

add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Content-Type-Options    "nosniff" always;
add_header X-Frame-Options           "SAMEORIGIN" always;
add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
add_header Permissions-Policy        "geolocation=(), camera=(), microphone=()" always;
EOF
```

Then in every vhost:

```nginx
server {
    listen 443 ssl;
    http2 on;
    server_name example.com;

    ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/example.com/chain.pem;

    include snippets/ssl-params.conf;
    # ...
}
```

Audit that every TLS vhost uses the snippet:

```bash
sudo grep -L "ssl-params" /etc/nginx/sites-enabled/*.conf
# Any file printed is missing the include.
```

## Inspecting live certificates with openssl

```bash
# Full handshake trace — cert chain, chosen protocol, chosen cipher:
openssl s_client -connect example.com:443 -servername example.com </dev/null

# Dates only:
openssl s_client -connect example.com:443 -servername example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -dates

# Subject, issuer, SANs:
openssl s_client -connect example.com:443 -servername example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -ext subjectAltName

# Full PEM body (to save a remote cert):
openssl s_client -connect example.com:443 -servername example.com </dev/null 2>/dev/null \
  | openssl x509 -outform pem > remote.crt

# Confirm old protocols are refused — both should show 'handshake failure':
openssl s_client -connect example.com:443 -tls1   </dev/null 2>&1 | grep -E "alert|handshake"
openssl s_client -connect example.com:443 -tls1_1 </dev/null 2>&1 | grep -E "alert|handshake"

# Confirm TLS 1.3 is accepted:
openssl s_client -connect example.com:443 -tls1_3 </dev/null 2>&1 | grep "Protocol"

# Force a specific cipher (check it is on your allow-list):
openssl s_client -connect example.com:443 -tls1_2 -cipher ECDHE-ECDSA-AES128-GCM-SHA256 </dev/null

# Check an OCSP staple is present and valid:
openssl s_client -connect example.com:443 -status </dev/null 2>&1 \
  | grep -A 17 "OCSP response"
```

Inspect a local cert file:

```bash
openssl x509 -in /etc/letsencrypt/live/example.com/fullchain.pem -text -noout
openssl x509 -in /etc/letsencrypt/live/example.com/cert.pem -noout -dates
openssl x509 -in /etc/letsencrypt/live/example.com/cert.pem -noout -ext subjectAltName
openssl x509 -in /etc/letsencrypt/live/example.com/cert.pem -noout -fingerprint -sha256

# Check the cert matches the key (the two modulus hashes must agree):
openssl x509 -noout -modulus -in /etc/letsencrypt/live/example.com/cert.pem | openssl md5
openssl rsa  -noout -modulus -in /etc/letsencrypt/live/example.com/privkey.pem | openssl md5
```

For an ECDSA key use `openssl pkey -noout -modulus` — but the more robust
check for ECDSA is to compare the public key hashes:

```bash
openssl x509 -pubkey -noout -in cert.pem | openssl sha256
openssl pkey -pubout     -in privkey.pem | openssl sha256
```

## Scanning with testssl.sh and sslscan

`testssl.sh` is the gold-standard offline TLS scanner. Install:

```bash
sudo apt install testssl.sh         # Ubuntu 22.04+ has it packaged
# or: git clone https://github.com/drwetter/testssl.sh.git
```

Run:

```bash
testssl.sh --severity HIGH example.com
testssl.sh --protocols example.com          # protocol support matrix
testssl.sh --vulnerable example.com         # Heartbleed, ROBOT, LUCKY13, etc.
testssl.sh --ciphers-per-proto example.com  # exact cipher suites per protocol
testssl.sh --headers example.com            # HSTS, HPKP, security headers
```

A cleaner one-command baseline:

```bash
sudo apt install sslscan
sslscan --no-colour example.com
```

Look for:

- **Preferred Server Cipher(s):** must list only AEAD (GCM / POLY1305) suites.
- **SSL Certificate:** `RSA Key Strength: 2048` or `ECDSA Curve Name:
  prime256v1|secp384r1`.
- **TLSv1.0 / 1.1:** must show `disabled`.

## SSL Labs / Mozilla Observatory

Online scanners you run from a browser or CI:

- **SSL Labs:** <https://www.ssllabs.com/ssltest/analyze.html?d=example.com>.
  Target grade A+. Anything below A means a misconfiguration. Check the box
  "Do not show the results on the boards" when testing admin hostnames.
- **Mozilla Observatory:**
  <https://observatory.mozilla.org/analyze/example.com>. Grades HTTP security
  headers alongside TLS. Target A+.
- **Hardenize / securityheaders.com:** complementary reports on header
  hygiene.

Run these after every TLS config change.

## Common misconfigurations and how to detect them

| Symptom | Likely cause | Fast check |
|---|---|---|
| Browser: `ERR_SSL_PROTOCOL_ERROR` | No overlap between client/server protocols | `openssl s_client -connect host:443 -tls1_2` |
| Browser: `NET::ERR_CERT_DATE_INVALID` | Cert expired or clock wrong | `certbot certificates`; `date -u` |
| Browser: `NET::ERR_CERT_AUTHORITY_INVALID` | Missing chain (leaf only, no intermediate) | `openssl s_client ... | grep depth` |
| Stapling shows `OCSP response: no response sent` | Wrong `ssl_trusted_certificate`; firewall blocks outbound :80 | `curl -v http://r3.o.lencr.org/` |
| SSL Labs shows `Weak Diffie-Hellman` | Missing `ssl_dhparam` or <2048 bits | `openssl dhparam -in dhparam.pem -text | head -1` |
| testssl.sh flags `Forward Secrecy: not available` | Cipher list includes non-DHE/ECDHE suites | Reload Mozilla Intermediate list verbatim |
| Mixed-content warnings | Hard-coded `http://` URLs in the app | `curl -s https://site | grep 'http://'` |
| HSTS missing on error pages | Header added without `always` keyword | `curl -sI https://site/nosuch` |

After every fix:

```bash
sudo nginx -t
sudo systemctl reload nginx
sudo testssl.sh --quiet --color 0 example.com
```

## Sources

- Canonical, *Ubuntu Server Guide* (20.04 LTS), firewall and security chapters
  — UFW fundamentals and Let's Encrypt workflow.
- Ghada Atef, *Mastering Ubuntu* (2023), security configuration chapter.
- Mozilla SSL Configuration Generator — <https://ssl-config.mozilla.org>.
- RFC 5246 (TLS 1.2), RFC 8446 (TLS 1.3), RFC 8996 (TLS 1.0/1.1 deprecation),
  RFC 6797 (HSTS), RFC 7469 (HPKP — deprecated).
- OpenSSL project manual pages — <https://www.openssl.org/docs/>.
- Nginx documentation — <https://nginx.org/en/docs/http/ngx_http_ssl_module.html>.
- Apache mod_ssl documentation — <https://httpd.apache.org/docs/2.4/mod/mod_ssl.html>.
- drwetter/testssl.sh — <https://testssl.sh>.
- Qualys SSL Labs — <https://www.ssllabs.com/ssltest/>.
