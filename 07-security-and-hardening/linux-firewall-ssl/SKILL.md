---
name: linux-firewall-ssl
description: Manage host firewalls and SSL/TLS certificates across both major Linux families — UFW on Debian/Ubuntu and firewalld (zone-based, firewall-cmd) on the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). Firewall rule management (view, add, remove, rate limiting, reload). Certbot operations on both families (issue cert with --nginx plugin, check expiry, force renew, dry run, add domains, troubleshoot renewal, renew timer). ECDSA certificates, TLSv1.2/1.3 only.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Firewall & SSL Management

## Distro support

Two-family skill. **UFW** is the Debian/Ubuntu firewall; the RHEL family
(Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) uses **firewalld** — a
zone-based model, not a flat allow-list. `certbot` works on both; only install
and the renew timer differ. The body below uses UFW/Debian; full RHEL detail is
in [`references/firewalld-reference.md`](references/firewalld-reference.md).

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Firewall | `ufw` | `firewalld` (`firewall-cmd`) |
| Show rules | `ufw status verbose` | `firewall-cmd --list-all` |
| Allow HTTP/HTTPS | `ufw allow 80,443/tcp` | `firewall-cmd --permanent --add-service={http,https}` |
| Allow a raw port | `ufw allow 9100/tcp` | `firewall-cmd --permanent --add-port=9100/tcp` |
| Apply changes | immediate | `firewall-cmd --reload` (permanent vs runtime!) |
| Enable on boot | `ufw enable` | `systemctl enable --now firewalld` |
| certbot install | `apt install certbot python3-certbot-nginx` | `dnf install certbot python3-certbot-nginx` (EPEL on RHEL/Rocky/Alma) |
| Renew timer | `certbot.timer` / `snap.certbot.renew.timer` | `certbot-renew.timer` |

In `sk-*` scripts use the `firewall_allow` helper from `common.sh`, which
targets whichever firewall is active. See
[`references/firewalld-reference.md`](references/firewalld-reference.md) and
[`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

## Use when

- Managing UFW rules on a server.
- Issuing, renewing, or debugging TLS certificates with certbot.
- Verifying HTTPS posture, renewal state, or TLS config for a site.

## Do not use when

- The task is broader web stack tuning or 502 troubleshooting; use `linux-webstack`.
- The task is user access or SSH key management; use `linux-access-control`.

## Required inputs

- The target ports, hostnames, or certificate names.
- Whether the change affects firewall policy, certificate lifecycle, or both.
- Any maintenance window or production-safety constraints.

## Workflow

1. Inspect the current UFW or certificate state before changing it.
2. Apply the specific rule or certbot action needed.
3. Validate renewal or HTTPS behavior after the change.
4. Record any follow-up work such as DNS fixes, rate limits, or expired chains.

## Quality standards

- Keep firewall rules minimal and intentional.
- Prefer validated, renewable TLS configurations over one-off fixes.
- Verify the live result after every certificate or firewall change.

## Anti-patterns

- Opening broad firewall ranges without a clear requirement.
- Renewing or reissuing certificates without understanding the failure mode.
- Changing HTTPS state without verifying DNS and web server readiness.

## Outputs

- The UFW or TLS action taken.
- The exact verification commands or checks performed.
- Any remaining renewal or exposure risk.

## References

- [`references/ufw-reference.md`](references/ufw-reference.md)
- [`references/firewalld-reference.md`](references/firewalld-reference.md)
- [`references/certbot-reference.md`](references/certbot-reference.md)
- [`references/ssl-config.md`](references/ssl-config.md)

**This skill is self-contained.** Every command below is a standard tool on its
family — `ufw` + `certbot` on Debian/Ubuntu, `firewall-cmd` (firewalld) +
`certbot` on the RHEL family (see
[`references/firewalld-reference.md`](references/firewalld-reference.md)). The
`sk-*` scripts in the **Optional fast path** section are convenience wrappers —
never required.

## UFW Firewall

```bash
sudo ufw status verbose                 # current rules
sudo ufw status numbered                # numbered for easy deletion

# Standard web server rule set:
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp
sudo ufw enable

# Add a rule
sudo ufw allow <port>/tcp
sudo ufw allow from <ip> to any port 22   # restrict SSH to trusted IP

# Remove a rule
sudo ufw status numbered
sudo ufw delete <number>

# Rate limiting (brute-force protection)
sudo ufw limit 22/tcp

# Logging
sudo ufw logging on
sudo tail -f /var/log/ufw.log
```

---

## SSL Certificates (Certbot)

```bash
# Issue new cert (nginx plugin — modifies config automatically)
sudo certbot --nginx -d example.com
sudo certbot --nginx -d example.com -d www.example.com

# Check all cert expiry
sudo certbot certificates

# Test auto-renewal
sudo certbot renew --dry-run

# Force renew
sudo certbot renew --force-renewal

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

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-firewall-ssl` installs:

| Task | Fast-path script |
|---|---|
| List certs, days-to-expiry, renewal timer | `sudo sk-cert-status` |
| Interactive UFW profile picker + apply | `sudo sk-ufw-reset` |
| Diff UFW rules against a baseline | `sudo sk-ufw-audit` |
| Force-renew cert + reload web server | `sudo sk-cert-renew --domain <d>` |

These are optional wrappers. The `ufw` and `certbot` commands above are the
source of truth.

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
