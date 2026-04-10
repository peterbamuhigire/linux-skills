# Zone File Syntax Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

A BIND zone file is plain text describing every DNS record in a zone. This reference covers every directive and record type you will use — `$TTL`, `$ORIGIN`, SOA, NS, A, AAAA, CNAME, MX, TXT, SRV, PTR, CAA — plus reverse zones, validation with `named-checkzone`, serial-bumping discipline, secondary setup with AXFR/IXFR, and six complete annotated zone files you can copy, edit, and deploy.

## Table of contents

1. [Zone file anatomy](#zone-file-anatomy)
2. [Directives: $TTL, $ORIGIN, $INCLUDE](#directives-ttl-origin-include)
3. [The SOA record](#the-soa-record)
4. [Record types in detail](#record-types-in-detail)
5. [TXT records: SPF, DKIM, DMARC](#txt-records-spf-dkim-dmarc)
6. [Reverse zones (in-addr.arpa and ip6.arpa)](#reverse-zones-in-addrarpa-and-ip6arpa)
7. [Validation: named-checkzone and named-checkconf](#validation-named-checkzone-and-named-checkconf)
8. [Serial-bumping discipline](#serial-bumping-discipline)
9. [Secondary (slave) configuration, AXFR, and IXFR](#secondary-slave-configuration-axfr-and-ixfr)
10. [Complete zone file examples](#complete-zone-file-examples)
11. [Sources](#sources)

---

## Zone file anatomy

Every record follows the same positional format:

```
[name] [ttl] [class] type rdata [; comment]
```

- **name** — owner of the record. If omitted, the previous record's name is reused. `@` means "the zone's origin". A name **without** a trailing dot is relative to `$ORIGIN`; **with** a trailing dot it's fully qualified.
- **ttl** — seconds; optional. If omitted, `$TTL` is used.
- **class** — practically always `IN`. The only other class you'll see is `CH` for `version.bind`.
- **type** — `SOA`, `NS`, `A`, `AAAA`, `CNAME`, `MX`, `TXT`, `SRV`, `PTR`, `CAA`, etc.
- **rdata** — type-specific right-hand side.
- **comment** — anything after `;` is ignored.

The trailing dot is the single biggest source of zone file bugs. `www` means `www.<origin>`. `www.` means the literal root-level name `www.` — and will break resolution.

## Directives: $TTL, $ORIGIN, $INCLUDE

- **`$TTL 86400`** — default TTL (seconds) for records that omit the TTL field. **Required** as the first directive; `named` rejects any zone that loads a record before `$TTL` is set.
- **`$ORIGIN example.com.`** — domain unqualified names are relative to. Defaults to the zone name.
- **`$INCLUDE /etc/bind/zones/example.com.dkim`** — pull in another file (DKIM keys, generated subdomains).

Common TTL values: `300` (staging), `3600` (daily-change), `86400` (default A/AAAA/CNAME/MX), `604800` (long-stable NS, apex).

## The SOA record

Every zone has exactly one SOA (Start of Authority):

```
@   IN  SOA  ns1.example.com. hostmaster.example.com. (
            2025011001  ; serial     — bump on every change (YYYYMMDDNN)
            3600        ; refresh    — secondary recheck interval (1 hour)
            900         ; retry      — retry after failed refresh (15 min)
            1209600     ; expire     — secondary gives up after this (2 weeks)
            86400 )     ; minimum    — negative-cache TTL (1 day)
```

- **Primary NS** — FQDN of the authoritative master, trailing dot mandatory.
- **Contact email** — real email with `@` replaced by `.`: `hostmaster@example.com` becomes `hostmaster.example.com.`. Escape literal dots in the local-part (`john\.doe.example.com.`).
- **Serial** — monotonic 32-bit integer. Secondaries compare this to decide whether to re-transfer. Use `YYYYMMDDNN` format; see [serial-bumping discipline](#serial-bumping-discipline).
- **Refresh** — how often a secondary polls the master SOA. `3600` is fine; NOTIFY makes this less critical.
- **Retry** — how long to wait after a failed refresh. Must be less than refresh.
- **Expire** — after this long without master contact the secondary stops answering. Set to at least a week.
- **Minimum** — RFC 2308 negative-cache TTL. This is **not** the default TTL (use `$TTL` for that); it's how long resolvers cache NXDOMAIN/NODATA answers.

Rule of thumb: `retry < refresh < expire`, and `expire >= 14 * refresh`.

## Record types in detail

**A — IPv4 address.** One A record per hostname per address. Multiple A records on the same name implement round-robin.

```
@           IN  A       203.0.113.10        ; apex
www         IN  A       203.0.113.10
api         IN  A       203.0.113.11
api         IN  A       203.0.113.12        ; round-robin
```

**AAAA — IPv6 address.** Same idea for 128-bit addresses.

```
@           IN  AAAA    2001:db8::10
```

**NS — nameserver.** At least two NS records at the apex are mandatory. Targets must be hostnames, never IPs. If a target lives inside the zone itself, add a *glue* A/AAAA record so resolvers can find it.

```
@           IN  NS      ns1.example.com.
@           IN  NS      ns2.example.com.
ns1         IN  A       203.0.113.10        ; glue
ns2         IN  A       203.0.113.20
```

**CNAME — alias.** Points one name at another. Rules: CNAME cannot coexist with any other record type on the same owner name, which means **no CNAME at the apex** (`@` already has SOA + NS). MX, NS, and SRV targets must resolve to A/AAAA — never point them at a CNAME.

```
ftp         IN  CNAME   www                 ; ftp -> www -> A
shop        IN  CNAME   myshop.shopify.com. ; external, trailing dot
```

**MX — mail exchanger.** Priority first (lower = preferred), then target hostname. Target must be an A/AAAA, not a CNAME.

```
@           IN  MX  10  mail.example.com.
@           IN  MX  20  mail2.example.com.
```

**TXT — free-form text.** Used for email auth (SPF, DKIM, DMARC), domain-ownership tokens (Google, Let's Encrypt DNS-01). See [TXT records](#txt-records-spf-dkim-dmarc).

**SRV — service location.** Format: `_service._proto.name. IN SRV priority weight port target.`

```
_xmpp-client._tcp   IN  SRV  10 0 5222 xmpp.example.com.
_xmpp-server._tcp   IN  SRV  10 0 5269 xmpp.example.com.
```

**PTR — reverse pointer.** IP-to-name. Only valid inside `in-addr.arpa` or `ip6.arpa` zones — see [reverse zones](#reverse-zones-in-addrarpa-and-ip6arpa).

**CAA — Certification Authority Authorization.** Declares which CAs may issue certs for this domain. RFC 8659.

```
@   IN  CAA  0 issue     "letsencrypt.org"
@   IN  CAA  0 issuewild "letsencrypt.org"
@   IN  CAA  0 iodef     "mailto:security@example.com"
```

Fields: flags (0 or 128), tag (`issue`, `issuewild`, `iodef`), value in quotes.

## TXT records: SPF, DKIM, DMARC

These belong to the email stack and are covered in depth in [`linux-mail-server`](../../linux-mail-server/). Quick versions:

```
; SPF — authorised senders
@   IN  TXT  "v=spf1 ip4:203.0.113.25 include:_spf.google.com -all"

; DKIM — public key; selector ("default") is chosen by the signer.
; TXT values over 255 chars MUST be split into multiple quoted strings
; inside parentheses — BIND concatenates them.
default._domainkey  IN  TXT ( "v=DKIM1; k=rsa; "
                              "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCB..." )

; DMARC — policy on SPF/DKIM failures
_dmarc  IN  TXT  "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com; pct=100"
```

## Reverse zones (in-addr.arpa and ip6.arpa)

A reverse zone maps an IP back to a hostname. The octets are reversed and appended to `in-addr.arpa`: `203.0.113.10` becomes `10.113.0.203.in-addr.arpa`. For IPv6, nibble-reversed hex is appended to `ip6.arpa` — use `dig -x` or `arpaname` to generate these; you rarely hand-type them.

Declare the zone over the network prefix. For `203.0.113.0/24`:

```bind
zone "113.0.203.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/db.203.0.113";
    allow-transfer { 203.0.113.20; };
};
```

You can only delegate reverse zones on byte boundaries (/8, /16, /24) without upstream cooperation (RFC 2317 classless delegation). For allocations smaller than /24 the ISP owns the reverse zone and must delegate or set PTRs for you.

## Validation: named-checkzone and named-checkconf

**Always validate before reload.** These tools are free; broken DNS is expensive.

```bash
sudo named-checkconf                     # validate named.conf + all includes
sudo named-checkconf -z                  # also load each zone file (thorough)

sudo named-checkzone example.com /etc/bind/zones/db.example.com
# zone example.com/IN: loaded serial 2025011001
# OK
```

Useful flags: `-i full` (integrity-check NS/MX/SRV targets), `-D` (dump canonical sorted zone to stdout), `-k fail` (fail on check-names errors). The tool validates RFC 1035 syntax, then semantics: every NS/MX/SRV target must resolve, no CNAMEs at the apex, no duplicate owner names with incompatible types.

Make this the reflex before every reload:

```bash
sudo named-checkconf && \
sudo named-checkzone example.com /etc/bind/zones/db.example.com && \
sudo rndc reload example.com
```

## Serial-bumping discipline

The SOA serial is how secondaries decide whether to pull a new copy. If the serial doesn't move, the change doesn't propagate. If you go backwards, secondaries silently ignore the change.

**Format:** `YYYYMMDDNN` — year, month, day, two-digit revision for that day (`01`–`99`). Example progression: `2025011001`, `2025011002` (same day, second change), `2025011101` (next day), `2025020101` (next month).

Rules: **bump on every change**, **once per reload**, **never roll backward** (the serial is a 32-bit unsigned int; going backward breaks replication), **use the dated format** for debuggability, **automate it** with a wrapper that increments `NN` or rolls to a new day. To force replication after a catastrophic rollback, bump well ahead (`9999999999`) and reset to date format the next day.

## Secondary (slave) configuration, AXFR, and IXFR

A secondary holds a read-only replica pulled from a master. Every production domain should have at least two NS records in different networks.

- **AXFR** — full zone transfer. Used the first time and whenever zones are out of sync.
- **IXFR** (RFC 1995) — incremental transfer: only records changed since a given serial. BIND does IXFR automatically if the master has a journal (`.jnl`), falls back to AXFR otherwise.
- **NOTIFY** — on serial change the master sends a NOTIFY to every NS and `also-notify` address, which triggers an immediate refresh instead of waiting for the SOA timer.

On the master:

```bind
zone "example.com" {
    type master;
    file "/etc/bind/zones/db.example.com";
    allow-transfer { 203.0.113.20; 203.0.113.21; };  // or: key "xfer-key";
    also-notify    { 203.0.113.20; 203.0.113.21; };
    notify yes;
};
```

On the secondary:

```bind
zone "example.com" {
    type slave;
    file "/var/cache/bind/db.example.com";   // writable by bind user
    masters { 203.0.113.10; };
};
```

Port 53/TCP must be open between master and secondary — AXFR/IXFR is TCP-only. Firewall blocks on TCP 53 are the #1 cause of silent slave failures. Verify propagation with `dig @master example.com SOA +short` vs `dig @slave example.com SOA +short` — the serials must match.

## Complete zone file examples

Each example is a complete file you can save, edit, validate with `named-checkzone`, and deploy. Placeholders: `example.com`, `203.0.113.10`, `2001:db8::10`.

### Example 1 — simple static website

One domain, one web server, no mail — the minimum viable zone.

```
$TTL 86400
$ORIGIN example.com.

@       IN  SOA ns1.example.com. hostmaster.example.com. (
                2025011001  ; serial (YYYYMMDDNN)
                3600        ; refresh 1h
                900         ; retry 15m
                1209600     ; expire 2w
                86400 )     ; minimum 1d

@       IN  NS      ns1.example.com.
@       IN  NS      ns2.example.com.
ns1     IN  A       203.0.113.10        ; glue — in-zone NS
ns2     IN  A       203.0.113.20

@       IN  A       203.0.113.10
@       IN  AAAA    2001:db8::10
www     IN  CNAME   @                    ; www -> apex
```

### Example 2 — website + mail + www

Adds MX with SPF, DKIM, DMARC placeholders, and apex CAA.

```
$TTL 86400
$ORIGIN example.com.

@       IN  SOA ns1.example.com. hostmaster.example.com. (
                2025011101 3600 900 1209600 86400 )

@       IN  NS      ns1.example.com.
@       IN  NS      ns2.example.com.
ns1     IN  A       203.0.113.10
ns2     IN  A       203.0.113.20

; ---- Web -------------------------------------------------------------
@       IN  A       203.0.113.10
@       IN  AAAA    2001:db8::10
www     IN  CNAME   @
api     IN  A       203.0.113.11

; ---- Mail ------------------------------------------------------------
@       IN  MX  10  mail.example.com.
mail    IN  A       203.0.113.25
mail    IN  AAAA    2001:db8::25

; SPF — only the mail host may send
@       IN  TXT     "v=spf1 ip4:203.0.113.25 ip6:2001:db8::25 -all"

; DKIM — paste your real public key; split at 255-char boundaries
default._domainkey  IN  TXT ( "v=DKIM1; k=rsa; "
                              "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCB..." )

; DMARC — quarantine failures, send reports
_dmarc  IN  TXT     "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com; pct=100"

; ---- CAA — only Let's Encrypt may issue certs -----------------------
@       IN  CAA     0 issue     "letsencrypt.org"
@       IN  CAA     0 issuewild "letsencrypt.org"
@       IN  CAA     0 iodef     "mailto:security@example.com"
```

### Example 3 — delegated subdomain

Parent zone `example.com` delegates `internal.example.com` to a different pair of nameservers (e.g. inside a data centre). The delegation lives in the parent; the child zone is a separate file on its own servers.

Parent zone extract (add to Example 2's file):

```
internal            IN  NS  ns1.dc.example.com.
internal            IN  NS  ns2.dc.example.com.
; Glue REQUIRED — ns1.dc.example.com lives *under* example.com
ns1.dc              IN  A   10.10.0.53
ns2.dc              IN  A   10.10.0.54
```

The child zone on `ns1.dc.example.com`:

```
$TTL 3600
$ORIGIN internal.example.com.

@       IN  SOA ns1.dc.example.com. hostmaster.example.com. (
                2025011102 3600 900 1209600 3600 )
@       IN  NS  ns1.dc.example.com.
@       IN  NS  ns2.dc.example.com.

db01    IN  A   10.10.0.101
db02    IN  A   10.10.0.102
app01   IN  A   10.10.1.101
```

### Example 4 — reverse zone for 203.0.113.0/24

Every A record in Example 2 should have a matching PTR record here — run `sk-dns-zone-check` to spot orphans.

```
$TTL 86400
$ORIGIN 113.0.203.in-addr.arpa.

@       IN  SOA ns1.example.com. hostmaster.example.com. (
                2025011101 3600 900 1209600 86400 )

@       IN  NS  ns1.example.com.
@       IN  NS  ns2.example.com.

; Left-hand side is the host octet within the /24.
10      IN  PTR example.com.
10      IN  PTR ns1.example.com.
11      IN  PTR api.example.com.
20      IN  PTR ns2.example.com.
25      IN  PTR mail.example.com.
```

### Example 5 — DNSSEC-signed zone (inline signing)

DNSSEC signing is performed by `dnssec-signzone` or BIND's inline signing — never hand-authored. A signed zone gains DNSKEY, RRSIG, NSEC/NSEC3, and (at the parent) DS records. Enable inline signing in `named.conf.local`:

```bind
zone "example.com" {
    type master;
    file "/var/lib/bind/db.example.com";   // writable by bind user
    inline-signing yes;
    auto-dnssec maintain;
    key-directory "/etc/bind/keys";
};
```

Generate the KSK and ZSK, then load them:

```bash
sudo -u bind dnssec-keygen -K /etc/bind/keys -a ECDSAP256SHA256 -f KSK example.com
sudo -u bind dnssec-keygen -K /etc/bind/keys -a ECDSAP256SHA256       example.com
sudo rndc loadkeys example.com
```

Finally publish the DS record at the parent (registrar) or DNSSEC is not actually active. The underlying zone file uses the same syntax as Example 2 — BIND adds the signing records automatically into a parallel `.signed` file.

### Example 6 — split-horizon zone

One domain, two files: external view returns public addresses, internal view returns RFC1918 addresses. Both files use the **same** zone name but different records.

External file `/etc/bind/zones/db.example.com.external`:

```
$TTL 86400
$ORIGIN example.com.

@       IN  SOA ns1.example.com. hostmaster.example.com. (
                2025011101 3600 900 1209600 86400 )
@       IN  NS  ns1.example.com.
@       IN  NS  ns2.example.com.
@       IN  A       203.0.113.10       ; PUBLIC
www     IN  A       203.0.113.10
mail    IN  A       203.0.113.25
```

Internal file `/etc/bind/zones/db.example.com.internal`:

```
$TTL 3600
$ORIGIN example.com.

@       IN  SOA ns1.example.com. hostmaster.example.com. (
                2025011101 3600 900 1209600 3600 )
@       IN  NS  ns1.example.com.
@       IN  A       10.0.0.10          ; PRIVATE — RFC1918
www     IN  A       10.0.0.10
mail    IN  A       10.0.0.25
intranet IN A       10.0.0.50          ; internal-only
db01    IN  A       10.0.1.11
db02    IN  A       10.0.1.12
```

Wire them up with matching views in `named.conf.local`:

```bind
acl "internal" { 10.0.0.0/8; 192.168.0.0/16; };

view "internal" {
    match-clients { internal; };
    recursion yes;
    zone "example.com" {
        type master;
        file "/etc/bind/zones/db.example.com.internal";
    };
    zone "." { type hint; file "/usr/share/dns/root.hints"; };
};

view "external" {
    match-clients { any; };
    recursion no;
    zone "example.com" {
        type master;
        file "/etc/bind/zones/db.example.com.external";
    };
};
```

Internal clients hit the `internal` view first (ACL match); external clients fall through to `external`. Keep the SOA serials in lockstep when you make parallel changes, and validate each file individually with `named-checkzone` before `rndc reload`.

---

## Sources

- *Linux Network Administrator's Guide, 2nd Edition* — Olaf Kirch & Terry Dawson (O'Reilly, 2000), Chapter 6, "Name Service and Resolver Configuration": *The DNS Database* (SOA, A, NS, CNAME, PTR, MX, HINFO record definitions), *Reverse Lookups* (`in-addr.arpa` delegation), *Writing the Master Files* (Examples 6.10–6.13: `named.ca`, `named.hosts`, `named.local`, `named.rev`), and *Verifying the Name Server Setup* (nslookup, dig).
- *Ubuntu Server Guide* (Ubuntu 20.04 LTS, Canonical, 2020), *Domain Name Service (DNS)* chapter: Forward Zone File layout (`$TTL`, SOA, NS, A, AAAA), Reverse Zone File layout, *Secondary Server* section (`allow-transfer`, `also-notify`, `type slave`, `masters { ... };`), *named-checkzone* section, *Common Record Types* (A, CNAME, MX, NS), and the serial-number discipline note (`yyyymmddss`).
- Supplementary: RFC 1035 (zone file format), RFC 1995 (IXFR), RFC 1996 (NOTIFY), RFC 2308 (negative caching and SOA minimum), RFC 8659 (CAA), and the BIND 9 Administrator Reference Manual's chapter on zone-file directives.
