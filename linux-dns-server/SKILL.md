---
name: linux-dns-server
description: Run and manage authoritative DNS servers on Ubuntu/Debian — BIND9 and unbound. Use for zone file authoring, record validation, zone reloads, reverse zones, and DNS server hardening. For client-side DNS resolution on a server, use linux-network-admin instead.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---

# Linux DNS Server

This skill owns **authoritative DNS serving** — running BIND9 or unbound as
a server that answers queries for zones you control.

It does **not** own:

- **Client-side DNS lookups** from a server (that's `linux-network-admin`
  via `sk-dns-check`).
- **MX records and email authentication** (that's `linux-mail-server`).
- **DNS records at a registrar** — those belong to whoever manages the
  domain at its registrar; this skill handles self-hosted authoritative DNS.

Informed by *Linux Network Administrator's Guide* chapters on BIND and
resolver configuration, with modern updates (BIND 9.18+, systemd integration).

---

## When to use

- Hosting authoritative zones for your own domains.
- Setting up a recursive resolver for an internal network.
- Validating zone files before reload.
- Debugging zone transfer failures or serial mismatches.
- Adding, removing, or editing DNS records in a managed zone.
- Setting up reverse DNS (in-addr.arpa / ip6.arpa).

## When NOT to use

- Looking up DNS from a server to debug outbound connectivity — use
  `linux-network-admin`'s `sk-dns-check`.
- Managing records at Cloudflare, Route53, or another cloud DNS — this
  toolkit targets self-hosted BIND/unbound only.

---

## Standing rules

1. **Always `named-checkconf` before reloading.** `sk-bind-reload` enforces
   this. A bad config takes down every zone.
2. **Always `named-checkzone` for every modified zone.** A bad zone file
   takes down that zone.
3. **Bump the serial on every change.** Format: `YYYYMMDDNN`. Slaves won't
   pull the change if the serial hasn't moved.
4. **Reverse zones must match forward zones.** For every A record that
   belongs to you, a PTR should exist in the in-addr.arpa zone you control
   (or your upstream provider must set it). `sk-dns-zone-check` flags
   orphans.
5. **Zone files live in `/etc/bind/zones/` by convention.** Permissions:
   `bind:bind`, mode `0644`.
6. **`rndc reload <zone>` is safer than `systemctl reload bind9`.** It
   reloads one zone at a time and won't flush caches unnecessarily.

---

## Typical workflows

### Adding a record to a managed zone

1. Edit `/etc/bind/zones/example.com.zone`.
2. Bump the SOA serial (YYYYMMDDNN).
3. `sk-bind-reload --zone example.com` — runs `named-checkzone`, then
   `rndc reload example.com`.
4. `sk-dns-zone-check example.com` — verifies from the server and from
   external.

### Validating a zone before import

```bash
sk-dns-zone-check --file /tmp/imported-zone.zone --domain example.com
```

Runs `named-checkzone` and dumps SOA/NS/A/MX/CNAME records for review.

### Serial mismatch debugging

When a slave isn't updating, compare serials:

```bash
dig @master  example.com SOA +short
dig @slave   example.com SOA +short
```

If they differ after a reload, check the slave's logs for zone transfer
errors — commonly firewall blocks on port 53/tcp.

---

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-dns-server
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-dns-zone-check | scripts/sk-dns-zone-check.sh | no | Validate a BIND zone file with `named-checkzone`, dump SOA/NS/A/MX, diff against previous snapshot. |
| sk-bind-reload | scripts/sk-bind-reload.sh | no | Run `named-checkconf`, `named-checkzone` for each modified zone, `rndc reload`, verify serial bumped. |

---

## See also

- `linux-network-admin` — client-side DNS lookups and netplan resolver config.
- `linux-mail-server` — MX records, SPF, DKIM, DMARC for email.
- `linux-firewall-ssl` — opening port 53 (TCP + UDP) for DNS serving.
