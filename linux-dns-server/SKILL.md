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

**This skill is self-contained.** Every command below is a standard
Ubuntu/Debian tool (`named`, `rndc`, `named-checkconf`, `named-checkzone`,
`dig`). The `sk-*` scripts in the **Optional fast path** section are
convenience wrappers — never required.

This skill owns **authoritative DNS serving** — running BIND9 or unbound
as a server that answers queries for zones you control.

It does **not** own:

- **Client-side DNS lookups** from a server — `linux-network-admin`.
- **MX records and email auth** — `linux-mail-server`.
- **DNS records at a registrar** — those belong to whoever manages the
  domain at its registrar; this skill handles self-hosted authoritative
  DNS.

Informed by *Linux Network Administrator's Guide* (BIND chapters) and
the Canonical *Ubuntu Server Guide* (BIND9 packaging).

---

## When to use

- Hosting authoritative zones for your own domains.
- Setting up a recursive resolver for an internal network.
- Validating zone files before reload.
- Debugging zone transfer failures or serial mismatches.
- Adding, removing, or editing DNS records in a managed zone.
- Setting up reverse DNS (in-addr.arpa / ip6.arpa).

## When NOT to use

- Debugging outbound DNS from a server — `linux-network-admin`'s
  diagnostics.
- Cloudflare / Route53 / Google Cloud DNS — those are managed DNS APIs.

---

## Standing rules

1. **Always `named-checkconf` before reloading.** A bad config takes
   down every zone.
2. **Always `named-checkzone` for every modified zone.** A bad zone
   file takes down that zone.
3. **Bump the serial on every change.** Format: `YYYYMMDDNN`. Slaves
   won't pull the change if the serial hasn't moved.
4. **Reverse zones must match forward zones.** Every A record you own
   should have a PTR in the in-addr.arpa zone you control (or upstream).
5. **Zone files live in `/etc/bind/zones/` by convention.** Permissions:
   `bind:bind`, mode `0644`.
6. **`rndc reload <zone>` is safer than `systemctl reload bind9`.** It
   reloads one zone at a time.
7. **Restrict recursion.** Only answer recursive queries from trusted
   networks. Open recursive resolvers are used in amplification attacks.

---

## Quick reference — manual commands

### Install and baseline

```bash
sudo apt install bind9 bind9-utils dnsutils

# Files land in:
#   /etc/bind/named.conf           — main config, don't edit directly
#   /etc/bind/named.conf.options   — global options
#   /etc/bind/named.conf.local     — your zones
#   /var/lib/bind/                 — dynamic state (slaves, journals)
#   /var/log/                      — if you configure file logging

sudo systemctl status bind9 --no-pager
sudo journalctl -u bind9 -n 50 --no-pager
```

### Validate and reload

```bash
# Validate main config
sudo named-checkconf

# Validate a specific zone file
sudo named-checkzone example.com /etc/bind/zones/example.com.zone

# Reload via rndc (preferred — doesn't flush cache)
sudo rndc reload                              # reload everything
sudo rndc reload example.com                  # reload one zone

# Dump the current cache (debugging)
sudo rndc dumpdb -cache
sudo less /var/cache/bind/named_dump.db

# Flush cache for a zone (after manual changes at upstream)
sudo rndc flush
```

### Query your own server

```bash
# Ask your BIND directly (bypass systemd-resolved)
dig @127.0.0.1 example.com SOA
dig @127.0.0.1 example.com NS
dig @127.0.0.1 example.com MX
dig @127.0.0.1 example.com A +all        # show all sections

# Check from outside (replace with your public IP)
dig @<public-ip> example.com SOA

# AXFR zone transfer test (from an allowed secondary)
dig @<master> example.com AXFR
```

### Adding a record

```bash
# 1. Edit the zone file
sudo nano /etc/bind/zones/example.com.zone

# 2. Bump the serial (YYYYMMDDNN format)
#    From 2026041001 to 2026041002 etc.

# 3. Validate
sudo named-checkzone example.com /etc/bind/zones/example.com.zone

# 4. Reload that zone only
sudo rndc reload example.com

# 5. Verify
dig @127.0.0.1 new-record.example.com A +short
```

Full BIND9 reference (`named.conf` structure, options, logging, views,
TSIG, rndc control channel, systemd integration, common errors) — see
[`references/bind9-reference.md`](references/bind9-reference.md).

Full zone file syntax reference (SOA, NS, A, AAAA, CNAME, MX, TXT, SRV,
PTR, CAA, reverse zones, slave config, 4–6 complete examples) — see
[`references/zone-file-syntax.md`](references/zone-file-syntax.md).

---

## Typical workflows

### Workflow: Adding a record to a managed zone

```bash
sudo nano /etc/bind/zones/example.com.zone
# Increment SOA serial
# Add the new record (A, CNAME, MX, TXT, etc.)

sudo named-checkzone example.com /etc/bind/zones/example.com.zone
sudo rndc reload example.com

dig @127.0.0.1 new.example.com A +short
```

### Workflow: Serial mismatch between master and slave

```bash
# Compare serials
dig @master.example.com  example.com SOA +short | awk '{print $3}'
dig @slave.example.com   example.com SOA +short | awk '{print $3}'

# If they differ after a master reload:
sudo journalctl -u bind9 -n 100 --no-pager | grep -i -E "transfer|notify"
# Look for: "transfer of 'example.com/IN' from ...: failed"
# Common cause: slave firewall blocks 53/tcp (AXFR is TCP)

# Force the slave to retry
sudo rndc retransfer example.com              # on the slave

# Check the journal log on the slave
sudo ls /var/lib/bind/
```

### Workflow: Validating a zone before import

```bash
# Against a file you received but haven't installed
named-checkzone example.com /tmp/imported-zone.zone

# Dump the parsed zone to verify what BIND sees
named-compilezone -o - example.com /tmp/imported-zone.zone | less
```

### Workflow: Setting up a reverse zone for your subnet

```bash
# For 192.0.2.0/24, the zone is 2.0.192.in-addr.arpa
sudo nano /etc/bind/named.conf.local
# Add a zone stanza pointing at /etc/bind/zones/db.192.0.2

# Create the zone file with SOA + NS + PTR records
# (see references/zone-file-syntax.md for the template)

sudo named-checkconf
sudo named-checkzone 2.0.192.in-addr.arpa /etc/bind/zones/db.192.0.2
sudo rndc reload

dig @127.0.0.1 -x 192.0.2.10 +short
```

---

## Troubleshooting / gotchas

- **Zone loaded but queries return SERVFAIL.** Check `named-checkconf`
  for missing includes. Check that the `zone` stanza in
  `named.conf.local` points at a file BIND can read (`bind:bind`, mode
  `0644`).
- **Serial didn't increment, slaves aren't pulling.** BIND compares
  serial numbers literally — a new file with the same serial is treated
  as identical. Always bump.
- **`rndc reload` works but queries show old data.** BIND caches
  recursive answers. `sudo rndc flush` clears the recursive cache; zone
  data is authoritative and updates immediately.
- **AXFR failing with "REFUSED".** Master's `allow-transfer` doesn't
  list the slave's IP, or TSIG key mismatch.
- **Running both `systemd-resolved` and `bind9`.** Port 53 conflict.
  Disable resolved's stub listener: `DNSStubListener=no` in
  `/etc/systemd/resolved.conf`, then `systemctl restart systemd-resolved`.
- **Logs going to syslog with nothing in `/var/log/named.log`.** BIND
  defaults to syslog (`journalctl -u bind9`). File logging requires
  explicit `logging { ... }` stanzas — see the reference.

---

## References

- [`references/bind9-reference.md`](references/bind9-reference.md) —
  full BIND9 reference: named.conf structure, options, logging, views,
  TSIG, rndc, systemd.
- [`references/zone-file-syntax.md`](references/zone-file-syntax.md) —
  zone file syntax with all record types, reverse zones, slave config,
  complete worked examples.
- Book: *Linux Network Administrator's Guide* — BIND chapters.
- Book: *Ubuntu Server Guide* — BIND9 package layout.
- Man pages: `named(8)`, `named.conf(5)`, `named-checkconf(8)`,
  `named-checkzone(8)`, `rndc(8)`.

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-dns-server` installs:

| Task | Fast-path script |
|---|---|
| Validate a zone file + snapshot records for diff | `sudo sk-dns-zone-check --file <path>` |
| Checked-reload (config + each zone + verify serial bumped) | `sudo sk-bind-reload [--zone <name>]` |

These are optional wrappers around `named-checkconf`, `named-checkzone`,
and `rndc`.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-dns-server
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-dns-zone-check | scripts/sk-dns-zone-check.sh | no | Validate a BIND zone file with `named-checkzone`, dump SOA/NS/A/MX, diff against previous snapshot. |
| sk-bind-reload | scripts/sk-bind-reload.sh | no | Run `named-checkconf`, `named-checkzone` for each modified zone, `rndc reload`, verify serial bumped. |
