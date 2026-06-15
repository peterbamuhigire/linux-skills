# firewalld reference (RHEL family)

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

`firewalld` is the default firewall manager on the RHEL family (Fedora, RHEL,
CentOS Stream, Rocky, Alma, Oracle). It is the RHEL-family counterpart to UFW
on Debian/Ubuntu. Both are front-ends over nftables/iptables; the **mental
model differs** — firewalld is **zone-based**, UFW is a flat allow/deny list.

Use this alongside [`ufw-reference.md`](ufw-reference.md). In `sk-*` scripts,
prefer the `firewall_allow` helper from `common.sh`, which targets whichever
firewall is active.

---

## Mental model: zones

Every network interface (and source) is bound to a **zone**. A zone is a named
trust level with its own set of allowed services/ports. Default zone on most
servers is `public`. Traffic is matched: source-based zone → interface zone →
default zone.

```bash
firewall-cmd --get-default-zone           # usually: public
firewall-cmd --get-active-zones           # zone -> interfaces/sources
firewall-cmd --get-zones                  # all defined zones
firewall-cmd --list-all                   # everything in the default zone
firewall-cmd --zone=public --list-all
```

Common zones: `drop` (deny all in, no reply), `block` (deny in, reply with
reject), `public` (default, selective allow), `internal`/`trusted` (lax),
`dmz`.

---

## The permanent/runtime split (the #1 gotcha)

firewalld keeps **two** configurations: the live **runtime** and the on-disk
**permanent**. Changes apply to runtime unless you pass `--permanent`, and
`--permanent` changes do **not** take effect until reloaded.

```bash
# Apply now AND persist (the safe default for two commands):
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload                 # load permanent into runtime

# Or: change runtime, then snapshot runtime -> permanent
sudo firewall-cmd --add-service=https       # runtime only (lost on reload)
sudo firewall-cmd --runtime-to-permanent    # persist current runtime
```

`--reload` re-reads permanent config and **drops runtime-only rules**. This is
the opposite of UFW, where `ufw allow` is immediately persistent.

---

## Services vs ports

firewalld ships named **services** (port+protocol bundles in
`/usr/lib/firewalld/services/`). Prefer services over raw ports when one exists.

```bash
firewall-cmd --get-services                 # all known service names
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --permanent --add-service=ssh

# Raw ports when no service exists
sudo firewall-cmd --permanent --add-port=9100/tcp     # node_exporter
sudo firewall-cmd --permanent --add-port=8000-8100/tcp

# Remove
sudo firewall-cmd --permanent --remove-service=http
sudo firewall-cmd --permanent --remove-port=9100/tcp

sudo firewall-cmd --reload
```

---

## UFW → firewalld translation

| Intent | UFW (Debian/Ubuntu) | firewalld (RHEL family) |
|---|---|---|
| Show rules | `ufw status verbose` | `firewall-cmd --list-all` |
| Default deny incoming | `ufw default deny incoming` | default zone `public` already rejects |
| Allow SSH | `ufw allow 22/tcp` | `--permanent --add-service=ssh` |
| Allow HTTP/HTTPS | `ufw allow 80,443/tcp` | `--permanent --add-service={http,https}` |
| Allow a raw port | `ufw allow 9100/tcp` | `--permanent --add-port=9100/tcp` |
| Allow from a source | `ufw allow from 10.0.0.0/8` | rich rule or assign source to `trusted` |
| Rate-limit SSH | `ufw limit 22/tcp` | rich rule with `limit value=…` |
| Delete a rule | `ufw delete allow 80/tcp` | `--permanent --remove-service=http` |
| Enable on boot | `ufw enable` | `systemctl enable --now firewalld` |
| Apply changes | (immediate) | `firewall-cmd --reload` |

---

## Source-based access and rich rules

```bash
# Trust a whole subnet (e.g. a management LAN)
sudo firewall-cmd --permanent --zone=trusted --add-source=10.0.0.0/24

# Allow a service only from one source (rich rule)
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" \
  source address="203.0.113.5" service name="ssh" accept'

# Rate-limit (UFW `limit` equivalent): 4 new SSH conns/min
sudo firewall-cmd --permanent --add-rich-rule='rule service name="ssh" \
  limit value="4/m" accept'

# Block a source
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" \
  source address="198.51.100.7" drop'

sudo firewall-cmd --reload
```

---

## Lifecycle & emergencies

```bash
sudo systemctl enable --now firewalld
firewall-cmd --state                        # running?
sudo firewall-cmd --panic-on                 # drop ALL traffic (emergency)
sudo firewall-cmd --panic-off
firewall-cmd --query-panic
```

---

## SSL / certbot on the RHEL family

`certbot` exists on both families; only the install path differs.

| Step | Debian/Ubuntu | RHEL family |
|---|---|---|
| Install | `apt install certbot python3-certbot-nginx` | `dnf install certbot python3-certbot-nginx` (via **EPEL** on RHEL/Rocky/Alma; main on Fedora) |
| Apache plugin | `python3-certbot-apache` | `python3-certbot-apache` |
| Renew timer | `certbot.timer` (systemd) or `snap.certbot.renew.timer` | `certbot-renew.timer` (systemd) |
| Webroot/standalone | identical | identical |

```bash
sudo dnf install -y certbot python3-certbot-nginx        # Fedora: no EPEL needed
sudo certbot --nginx -d example.com -d www.example.com
sudo certbot renew --dry-run
systemctl list-timers '*certbot*'
```

**firewalld + certbot HTTP-01:** open `http`/`https` *before* issuing, or the
ACME challenge fails:

```bash
sudo firewall-cmd --permanent --add-service=http --add-service=https
sudo firewall-cmd --reload
```

ECDSA keys and TLSv1.2/1.3-only config are identical across families (it's a
property of the cert and the web-server config, not the distro). See
[`ssl-config.md`](ssl-config.md).

---

## References

- [`ufw-reference.md`](ufw-reference.md) — the Debian/Ubuntu counterpart.
- [`certbot-reference.md`](certbot-reference.md) — certbot operations (portable).
- [`ssl-config.md`](ssl-config.md) — TLS hardening (portable).
- Man pages: `firewall-cmd(1)`, `firewalld.zones(5)`, `firewalld.richlanguage(5)`.
- Fedora/RHEL docs: "Using and configuring firewalld".
