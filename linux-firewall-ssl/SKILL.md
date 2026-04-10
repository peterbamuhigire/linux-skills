---
name: linux-firewall-ssl
description: Manage UFW firewall and SSL/TLS certificates on Ubuntu/Debian servers. UFW rule management (view, add, remove, rate limiting). Certbot operations (issue cert with --nginx plugin, check expiry, force renew, dry run, add domains, troubleshoot renewal). ECDSA certificates, TLSv1.2/1.3 only.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Firewall & SSL Management

## UFW Firewall

```bash
sudo ufw status verbose                 # current rules
sudo ufw status numbered                # numbered for easy deletion

# Interactive profile picker (web-server / bastion / db / custom):
sudo sk-ufw-reset

# Audit current rules against a baseline:
sudo sk-ufw-audit

# Manual rule management:
sudo ufw allow <port>/tcp
sudo ufw allow from <ip> to any port 22   # restrict SSH to trusted IP
sudo ufw delete <number>
sudo ufw limit 22/tcp                    # rate-limit brute force
sudo ufw logging on && sudo tail -f /var/log/ufw.log
```

---

## SSL Certificates (Certbot)

```bash
# Quick status report:
sudo sk-cert-status

# Issue new cert (nginx plugin — modifies config automatically)
sudo certbot --nginx -d example.com
sudo certbot --nginx -d example.com -d www.example.com

# Force renew + reload web server:
sudo sk-cert-renew --domain example.com

# Test auto-renewal
sudo certbot renew --dry-run

# Add domain to existing cert
sudo certbot --nginx --expand -d existing.com -d new.com

# Check renewal timer
sudo systemctl status certbot.timer
```

---

## Troubleshoot Renewal Failure

Every HTTP server block needs this for ACME challenge:
```nginx
location /.well-known/acme-challenge/ { root /var/www/html; }
```

```bash
# Verify all vhosts have it:
sudo grep -r "acme-challenge" /etc/nginx/sites-enabled/

# Test challenge path is reachable:
curl -s http://example.com/.well-known/acme-challenge/test
# Should return 404, not connection refused

# Debug renewal:
sudo certbot renew --dry-run --debug
sudo journalctl -u certbot --no-pager | tail -30
```

Full SSL parameters and cipher config: `references/ssl-config.md`

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-firewall-ssl
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-cert-status | scripts/sk-cert-status.sh | yes | List all certbot certs, days-to-expiry, domains covered, renewal timer state. |
| sk-ufw-reset | scripts/sk-ufw-reset.sh | no | Interactive UFW wizard: pick profile (web-server / bastion / db / custom), apply, enable. |
| sk-ufw-audit | scripts/sk-ufw-audit.sh | no | Diff active UFW rules against a baseline file; flag drift. |
| sk-cert-renew | scripts/sk-cert-renew.sh | no | Force certbot renewal for one or all domains, reload nginx/apache on success. |
