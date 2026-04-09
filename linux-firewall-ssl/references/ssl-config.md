# SSL Configuration Reference

## ssl-params.conf (/etc/nginx/snippets/ssl-params.conf)

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;

add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), camera=(), microphone=()" always;
```

Every SSL vhost must include:
```nginx
include snippets/ssl-params.conf;
```

Verify all SSL vhosts include it:
```bash
sudo grep -r "ssl-params" /etc/nginx/sites-enabled/
```

## Check TLS Version Quality

```bash
# Must not accept TLSv1.0 or TLSv1.1:
openssl s_client -connect <domain>:443 -tls1 2>&1 | grep -E "handshake|alert"
openssl s_client -connect <domain>:443 -tls1_1 2>&1 | grep -E "handshake|alert"
# Both should show: handshake failure

# Check what protocols are accepted:
nmap --script ssl-enum-ciphers -p 443 <domain> 2>/dev/null | grep -E "TLS|SSL"
```

## Certificate Key Type (ECDSA vs RSA)

```bash
sudo certbot certificates | grep "Certificate Path"
# Check key type:
openssl x509 -in /etc/letsencrypt/live/<domain>/cert.pem -text -noout | grep "Public Key"
```

Issue ECDSA cert (preferred):
```bash
sudo certbot --nginx -d <domain> --key-type ecdsa --elliptic-curve secp384r1
```

## phpMyAdmin SSL — Restrict + Protect

```apache
# In Apache vhost for phpMyAdmin:
<Directory /usr/share/phpmyadmin>
    AllowOverride All
    Require ip <your-trusted-ip>
    Require ip 127.0.0.1
</Directory>
```

## OpenSSL — Inspect and Verify Certificates

```bash
# Show cert details (expiry, issuer, SANs):
openssl x509 -in /etc/letsencrypt/live/<domain>/cert.pem -text -noout
openssl x509 -in /etc/letsencrypt/live/<domain>/cert.pem -noout -dates

# Verify cert against CA bundle:
openssl verify -CAfile /etc/ssl/certs/ca-certificates.crt /etc/letsencrypt/live/<domain>/cert.pem

# Test live TLS connection — shows cert chain, protocol, cipher:
openssl s_client -connect <domain>:443 -servername <domain>

# Test that old protocols are refused:
openssl s_client -connect <domain>:443 -tls1   2>&1 | grep -E "handshake|alert"
openssl s_client -connect <domain>:443 -tls1_1 2>&1 | grep -E "handshake|alert"
# Both should return: handshake failure

# Check OCSP stapling response:
openssl s_client -connect <domain>:443 -status 2>&1 | grep -A5 "OCSP response"

# Generate a self-signed cert (testing/internal use):
openssl req -newkey rsa:2048 -nodes -keyout server.key -x509 -days 365 -out server.crt

# Generate with EC key (preferred — stronger, lighter):
openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
    -keyout cert.key.x509 -out cert.crt -days 3650

# Generate a CSR + RSA key (to send to a CA):
openssl req --out CSR.csr -new -newkey rsa:2048 -nodes -keyout server-privatekey.key

# Generate a CSR with an EC key (two-step):
openssl genpkey -algorithm EC -out eckey.pem -pkeyopt ec_paramgen_curve:P-384 -pkeyopt ec_param_enc:named_curve
openssl req -new -key eckey.pem -out eckey.csr
```

## Apache TLS Hardening (/etc/apache2/mods-enabled/ssl.conf)

```apache
# Disable all protocols older than TLSv1.3:
SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1 -TLSv1.2

# Restart Apache after changes:
# sudo systemctl restart apache2
```

Check effective TLS config with sslscan (see monitoring-commands.md).

## UFW Firewall — Essential Commands

```bash
# Status and enable:
sudo ufw status
sudo systemctl status ufw
sudo ufw enable

# Allow / deny ports:
sudo ufw allow 22/tcp          # SSH (TCP only)
sudo ufw allow 443             # HTTPS (both TCP and UDP)
sudo ufw allow 53              # DNS (both protocols)
sudo ufw deny  8080/tcp        # block a port

# Reload after editing /etc/ufw/before.rules:
sudo ufw reload

# View underlying iptables rules (Ubuntu 20.04):
sudo iptables -L
sudo iptables -t mangle -L
sudo ip6tables -L

# View nftables rules (Ubuntu 22.04+):
sudo nft list ruleset
```
