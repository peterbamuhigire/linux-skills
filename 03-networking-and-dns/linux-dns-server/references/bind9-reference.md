# BIND9 Reference (Ubuntu/Debian)

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

BIND9 is the reference implementation of DNS on Linux, packaged on Ubuntu and Debian as `bind9`. This reference covers the on-disk layout, the split `named.conf` structure Ubuntu ships, every option you will actually touch in `named.conf.options`, views for split-horizon, TSIG and `rndc` for authenticated control, logging channels, systemd integration, and a triage chart for the errors you will hit in production. Treat it as the working knowledge you need before opening any BIND configuration file on a real server.

## Table of contents

1. [Install and package layout](#install-and-package-layout)
2. [The split named.conf structure](#the-split-namedconf-structure)
3. [named.conf.options in detail](#namedconfoptions-in-detail)
4. [named.conf.local: declaring zones](#namedconflocal-declaring-zones)
5. [Views (split-horizon DNS)](#views-split-horizon-dns)
6. [Logging: channels and categories](#logging-channels-and-categories)
7. [rndc control channel](#rndc-control-channel)
8. [TSIG keys for authenticated transfers and updates](#tsig-keys-for-authenticated-transfers-and-updates)
9. [Running as the bind user](#running-as-the-bind-user)
10. [systemd integration](#systemd-integration)
11. [Common errors and recovery](#common-errors-and-recovery)
12. [Sources](#sources)

---

## Install and package layout

Install BIND9 and the query utilities on Ubuntu or Debian:

```bash
sudo apt update
sudo apt install bind9 bind9utils bind9-doc dnsutils
```

Package contents, after install:

| Path | Purpose |
|---|---|
| `/etc/bind/` | All configuration files. Owned `root:bind`, mode `0755`. |
| `/etc/bind/named.conf` | Top-level config. In Ubuntu, contains only `include` statements. |
| `/etc/bind/named.conf.options` | Global options: recursion, forwarders, listen-on, query ACLs, DNSSEC. |
| `/etc/bind/named.conf.local` | Your zone declarations. Add new zones here. |
| `/etc/bind/named.conf.default-zones` | Default built-in zones: `localhost`, root hints. Leave alone. |
| `/etc/bind/db.*` | Seed zone files shipped by the package (`db.local`, `db.127`, `db.empty`). |
| `/etc/bind/rndc.key` | TSIG key auto-generated at install; lets `rndc` talk to `named`. |
| `/etc/bind/bind.keys` | Root zone DNSKEYs for DNSSEC validation (from `dns-root-data`). |
| `/var/cache/bind/` | Working directory. Slave zone and DDNS journals. AppArmor-writable. |
| `/var/lib/bind/` | Alternative writable location for zones that accept dynamic updates. |
| `/var/log/named/` | Custom log directory you create and `chown bind:bind` (not default). |
| `/usr/share/dns/root.hints` | Root hints file (IANA root servers), from the `dns-root-data` package. |
| `/usr/sbin/named` | The `named` daemon. |
| `/usr/sbin/rndc` | Control tool. |
| `/usr/sbin/named-checkconf` | Lint `named.conf`. |
| `/usr/sbin/named-checkzone` | Lint a zone file. |
| `/lib/systemd/system/named.service` | systemd unit, aliased as `bind9.service`. |

Rule of thumb:

- Static (hand-authored) zones live in `/etc/bind/zones/`.
- Dynamic (DDNS or `nsupdate`) zones live in `/var/lib/bind/` so the `bind` user can write journal files next to them.

## The split named.conf structure

Ubuntu/Debian ship `named.conf` as nothing but includes, keeping each concern in its own file. Do not add zones to `named.conf` directly — Ubuntu upgrades may overwrite it.

`/etc/bind/named.conf`:

```bind
// Top-level config. Do not edit — include only.
include "/etc/bind/named.conf.options";
include "/etc/bind/named.conf.local";
include "/etc/bind/named.conf.default-zones";
```

`/etc/bind/named.conf.default-zones` (shipped content, do not edit):

```bind
zone "." {
    type hint;
    file "/usr/share/dns/root.hints";
};

zone "localhost" {
    type master;
    file "/etc/bind/db.local";
};

zone "127.in-addr.arpa" {
    type master;
    file "/etc/bind/db.127";
};

zone "0.in-addr.arpa" {
    type master;
    file "/etc/bind/db.0";
};

zone "255.in-addr.arpa" {
    type master;
    file "/etc/bind/db.255";
};
```

Your own zones go in `named.conf.local`. Your knobs go in `named.conf.options`.

## named.conf.options in detail

This is the single most consequential file in a BIND install. A bad `options` block takes down every zone.

Production-grade `/etc/bind/named.conf.options` for an authoritative server that also resolves for the local network:

```bind
// ACLs — define once, reference below.
acl "trusted" {
    127.0.0.0/8;
    10.0.0.0/8;
    192.168.0.0/16;
};

options {
    // 1. Working directory. Must be writable by the bind user.
    directory "/var/cache/bind";

    // 2. Listen sockets. Lock to specific addresses in production.
    //    Otherwise named binds every interface and exposes a public resolver.
    listen-on { 127.0.0.1; 203.0.113.10; };
    listen-on-v6 { ::1; };

    // 3. Who may query at all. Default is any — tighten to stop open resolvers.
    allow-query { any; };

    // 4. Who may query for recursive answers.
    //    If you are authoritative-only, set this to { none; }.
    allow-recursion { trusted; };

    // 5. Who may request a zone transfer (AXFR/IXFR).
    //    Always deny by default and whitelist per-zone.
    allow-transfer { none; };

    // 6. Do you resolve queries for domains you are not authoritative for?
    //    "no" = authoritative-only server. "yes" = recursive resolver.
    recursion yes;

    // 7. Forwarders: upstream resolvers to ask before walking the root.
    //    Useful when the server is behind a firewall that blocks outbound port 53.
    forwarders {
        1.1.1.1;
        8.8.8.8;
    };
    forward only;           // only = never fall back to root. first = try forwarders then fall back.

    // 8. DNSSEC validation on recursive lookups. Default auto uses bind.keys.
    dnssec-validation auto;

    // 9. Don't advertise the BIND version to every attacker.
    version "not-available";

    // 10. Rate-limit identical answers — basic DNS amplification defence.
    rate-limit {
        responses-per-second 15;
        window 5;
    };

    // 11. Quadruple the default log stanza size.
    //    Production logs get chatty fast.
    max-cache-size 256M;

    // 12. IPv6 listen — leave enabled unless you know v6 is off.
    // listen-on-v6 { any; };

    // Auth-only mode? Set these instead:
    // recursion no;
    // allow-recursion { none; };
    // allow-query-cache { none; };
};
```

Key options:

- `directory` — every relative path in `named.conf` is resolved against this; must be owned by `bind:bind`.
- `listen-on` / `listen-on-v6` — which interfaces `named` binds. Default `any` creates an open resolver on every box.
- `allow-query` / `allow-recursion` / `allow-transfer` — ACLs. Recursive and transfer defaults must be tightened or you ship an amplification DDoS weapon and leak the full zone.
- `recursion` — master switch for recursive resolution. Authoritative-only servers use `recursion no`.
- `forwarders` / `forward only` — chain to an upstream resolver. `forward only` never falls back to the root; useful when outbound DNS is firewalled.
- `dnssec-validation auto` — validate DNSSEC signatures using trust anchors in `/etc/bind/bind.keys`.
- `version` — string returned to `dig version.bind chaos txt`. Hiding it slows fingerprinting.
- `rate-limit` — Response Rate Limiting (RRL), throttles repeated identical answers to blunt reflection attacks.
- `max-cache-size` — hard cap on the resolver cache.

## named.conf.local: declaring zones

Every authoritative zone you serve is declared here. Keep related forward and reverse zones next to each other.

```bind
// Forward primary zone.
zone "example.com" {
    type master;
    file "/etc/bind/zones/db.example.com";
    allow-transfer { 203.0.113.20; };   // secondary NS
    also-notify    { 203.0.113.20; };   // push NOTIFY on serial change
};

// Reverse primary zone for 203.0.113.0/24.
zone "113.0.203.in-addr.arpa" {
    type master;
    file "/etc/bind/zones/db.203.0.113";
    allow-transfer { 203.0.113.20; };
    also-notify    { 203.0.113.20; };
};

// Secondary (slave) of a zone we do not own.
zone "partner.net" {
    type slave;
    file "/var/cache/bind/db.partner.net";
    masters { 198.51.100.5; };
};

// Stub zone — track authoritative NS of a child without transferring records.
zone "internal.example.com" {
    type stub;
    file "/var/cache/bind/db.internal.example.com";
    masters { 10.0.0.2; };
};
```

Zone type reference:

| Type | Meaning | File writable? |
|---|---|---|
| `master` | This server is authoritative. You author the zone file. | Hand-edited. |
| `slave` | Pulled via AXFR/IXFR from `masters`. | Written by `named`, must live under `/var/cache/bind`. |
| `stub` | Like slave but only NS + glue. Rare. | Written by `named`. |
| `hint` | Root server bootstrap list. Only `.` uses this. | Shipped with package. |
| `forward` | Delegate all queries for this zone to forwarders. No local data. | None. |

Per-zone options worth knowing:

- `allow-transfer { ... };` — per-zone AXFR ACL; overrides global.
- `allow-update { key "ddns-key"; };` — enable dynamic updates signed by a TSIG key.
- `also-notify { ip; };` — push NOTIFY to secondaries that are not listed in the zone's NS records.
- `notify explicit;` — only NOTIFY addresses in `also-notify`, not NS records.
- `masterfile-format text;` — keep zone file human-readable (the default). Set to `raw` for binary speed-up.

## Views (split-horizon DNS)

A view returns different answers to different clients — typically, internal clients see RFC1918 addresses and external clients see public ones. Once you define any `view`, **every** `zone` must live inside a view.

```bind
acl "internal" {
    10.0.0.0/8;
    192.168.0.0/16;
};

acl "external" { any; };

view "internal" {
    match-clients { internal; };
    recursion yes;

    zone "example.com" {
        type master;
        file "/etc/bind/zones/db.example.com.internal";
    };

    // Include default zones inside the view.
    zone "." { type hint; file "/usr/share/dns/root.hints"; };
    zone "localhost" { type master; file "/etc/bind/db.local"; };
};

view "external" {
    match-clients { external; };
    recursion no;       // authoritative-only for outsiders

    zone "example.com" {
        type master;
        file "/etc/bind/zones/db.example.com.external";
    };
};
```

Rules:

- Views are evaluated top-to-bottom. Put the most specific ACL first.
- A single zone name can exist in multiple views with different files — that is the whole point.
- `match-clients` is evaluated against the source IP of the query (or the TSIG key name, if signed).

## Logging: channels and categories

BIND logging has two halves:

- **Channel** — *where* log messages go (file, syslog, null).
- **Category** — *what* class of messages go to which channels.

The default if you configure nothing:

```bind
logging {
    category default { default_syslog; default_debug; };
    category unmatched { null; };
};
```

Production logging block that splits queries, security events, and general errors into separate files:

```bind
logging {
    // --- channels: where messages land ---

    channel default_log {
        file "/var/log/named/default.log" versions 5 size 20m;
        severity info;
        print-time yes;
        print-severity yes;
        print-category yes;
    };

    channel query_log {
        file "/var/log/named/query.log" versions 3 size 50m;
        severity info;
        print-time yes;
    };

    channel security_log {
        file "/var/log/named/security.log" versions 5 size 20m;
        severity info;
        print-time yes;
        print-category yes;
    };

    // --- categories: what goes where ---

    category default    { default_log; };
    category general    { default_log; };
    category queries    { query_log; };       // needs `querylog yes;` or rndc querylog on
    category security   { security_log; };
    category client     { security_log; };
    category resolver   { default_log; };
    category xfer-in    { default_log; };
    category xfer-out   { default_log; };
    category notify     { default_log; };
    category dnssec     { default_log; };
    category lame-servers { null; };          // noisy, usually safe to drop
};
```

Before restart, create the log directory and set ownership — `named` runs as `bind` and AppArmor limits where it can write:

```bash
sudo mkdir -p /var/log/named
sudo chown bind:bind /var/log/named
sudo chmod 0750 /var/log/named
```

Severity levels, lowest to highest: `debug [level]`, `info`, `notice`, `warning`, `error`, `critical`, `dynamic`. A channel with `severity debug 3` captures everything including detailed debug traces.

Toggle query logging at runtime without reloading:

```bash
sudo rndc querylog on
sudo rndc querylog off
```

## rndc control channel

`rndc` is the authenticated control channel for `named`. Ubuntu ships it pre-configured: the install script generates `/etc/bind/rndc.key` and both `rndc` and `named` read it.

Default `/etc/bind/rndc.key`:

```bind
key "rndc-key" {
    algorithm hmac-sha256;
    secret "base64-random-secret-generated-at-install==";
};
```

`named` picks it up automatically via `/etc/bind/named.conf` (Ubuntu ships this include):

```bind
include "/etc/bind/rndc.key";

controls {
    inet 127.0.0.1 port 953
        allow { 127.0.0.1; } keys { "rndc-key"; };
};
```

Common `rndc` commands — memorise these, they are what you reach for daily:

```bash
sudo rndc status                    # daemon version, zone count, load
sudo rndc reload                    # reload config + all zones (no restart)
sudo rndc reload example.com        # reload ONE zone only — safer
sudo rndc reconfig                  # reload config, touch only changed zones
sudo rndc flush                     # wipe the resolver cache
sudo rndc flushname example.com     # wipe one name from cache
sudo rndc retransfer example.com    # force a slave to re-pull from master
sudo rndc notify example.com        # send NOTIFY to secondaries now
sudo rndc freeze example.com        # stop DDNS updates, allow hand-editing
sudo rndc thaw example.com          # re-enable DDNS after editing
sudo rndc querylog on               # runtime query logging toggle
sudo rndc stats                     # dump stats to named.stats
sudo rndc dumpdb -cache             # dump cache to named_dump.db
```

Key rule: prefer `rndc reload <zone>` over `systemctl reload bind9`. The single-zone reload does not flush the resolver cache and does not touch unrelated zones.

Remote `rndc` (manager station controlling a remote `named`) — generate a dedicated key:

```bash
sudo rndc-confgen -a -k remote-key -c /etc/bind/remote.key
```

Then on the server, bind the control channel to an interface and limit by IP:

```bind
controls {
    inet 203.0.113.10 port 953
        allow { 203.0.113.99; } keys { "remote-key"; };
};
```

Copy `/etc/bind/remote.key` to the operator station and reference it with `rndc -k /path/to/remote.key -s 203.0.113.10`.

## TSIG keys for authenticated transfers and updates

TSIG (Transaction Signature) uses a shared HMAC secret to prove that a DNS message really came from who it says it did. Use cases: authenticating zone transfers between master and slave, and authenticating dynamic updates from a client.

Generate a key:

```bash
sudo tsig-keygen -a hmac-sha256 xfer-key > /etc/bind/keys/xfer.key
sudo chown root:bind /etc/bind/keys/xfer.key
sudo chmod 0640 /etc/bind/keys/xfer.key
```

Result:

```bind
key "xfer-key" {
    algorithm hmac-sha256;
    secret "abcdef0123456789base64secret==";
};
```

Include on both master and slave:

```bind
// /etc/bind/named.conf.local on BOTH servers
include "/etc/bind/keys/xfer.key";
```

On the master, require the key for AXFR:

```bind
zone "example.com" {
    type master;
    file "/etc/bind/zones/db.example.com";
    allow-transfer { key "xfer-key"; };
};
```

On the slave, present the key when contacting the master:

```bind
server 203.0.113.10 {
    keys { "xfer-key"; };
};

zone "example.com" {
    type slave;
    file "/var/cache/bind/db.example.com";
    masters { 203.0.113.10; };
};
```

Same pattern for DDNS updates: generate a second key (`ddns-key`), reference it in `allow-update { key "ddns-key"; };`, and point `nsupdate -k` at it.

## Running as the bind user

The Debian package runs `named` as the unprivileged `bind` user by default, enforced via `/etc/default/named`:

```bash
# /etc/default/named
OPTIONS="-u bind"
```

File permissions that matter:

| Path | Owner | Mode | Notes |
|---|---|---|---|
| `/etc/bind/` | `root:bind` | `2755` | Readable by `named`. |
| `/etc/bind/named.conf*`, `/etc/bind/zones/*.zone` | `root:bind` | `0644` | Readable by `named`. |
| `/var/cache/bind/` | `bind:bind` | `0775` | Slave zones and journals. Writable. |
| `/var/lib/bind/` | `bind:bind` | `0775` | DDNS zone files. Writable. |
| `/var/log/named/` | `bind:bind` | `0750` | You create it. |

AppArmor profile `/etc/apparmor.d/usr.sbin.named` restricts which paths `named` may read or write. If you move zone files or logs outside the defaults, add a matching `rw` or `r` line to the profile — otherwise you get silent permission errors. Reload with `sudo apparmor_parser -r /etc/apparmor.d/usr.sbin.named`.

## systemd integration

The unit is `named.service`, aliased as `bind9.service` — both names work.

```bash
sudo systemctl status bind9           # state, PID, last log lines
sudo systemctl restart bind9          # full restart — drops cache
sudo systemctl reload bind9           # SIGHUP — reload config, keep cache
sudo systemctl enable bind9           # start at boot

sudo journalctl -u bind9                 # all logs for the unit
sudo journalctl -u bind9 -f              # follow
sudo journalctl -u bind9 -p err          # errors only
sudo journalctl -u bind9 -b              # since last boot
```

Rule: always `sudo named-checkconf` before `sudo systemctl reload bind9`. A bad config file makes `named` fail to reload (old config keeps running) or, on full restart, fail to start at all.

## Common errors and recovery

| Error | Cause | Fix |
|---|---|---|
| `loading configuration: file not found` | `named-checkconf` can't find an `include`d file. | Correct the path; confirm `0644` and readable by `root:bind`. |
| `zone .../IN: loading master file ...: file not found` | Zone file missing at the path in the `zone` stanza. | Create the file or correct the `file "..."` line. |
| `no TTL specified; zone rejected` | Missing `$TTL` directive at the top of the zone file. | Add `$TTL 86400` as the first line. |
| `bad owner name (check-names)` | Record name has an illegal character (e.g. underscore). | Correct the name, or relax with `check-names warn;` (not recommended). |
| `journal file .jnl is out of date` | DDNS journal inconsistent after hand-editing a dynamic zone. | `rndc freeze example.com`, remove the `.jnl`, edit, `rndc thaw example.com`. |
| `refresh: unexpected rcode (REFUSED) from master` | Master refusing AXFR from this slave. | On master: add slave IP or TSIG key to `allow-transfer`. Check firewall for TCP 53. |
| `serial received from master < ours` | Master was rolled back below the slave's serial. | Bump the master serial past the slave's, reload. |
| `query (cache) denied` | Recursive query rejected by `allow-recursion`. | Add the client to the `trusted` ACL, or accept the refusal. |
| `systemd-resolved is using port 53` | `systemd-resolved` binds 127.0.0.53:53 and blocks `named`. | `sudo systemctl disable --now systemd-resolved` and repoint `/etc/resolv.conf`; or set `listen-on { 203.0.113.10; };` so they coexist. |
| `rndc: connect failed: 127.0.0.1#953: connection refused` | `named` not running, or no `controls` stanza on 127.0.0.1. | `systemctl status bind9`; check `named.conf` for `controls { inet 127.0.0.1 ... };`; check `rndc.key` is readable. |

Diagnostic first-line commands, in the order you should run them:

```bash
sudo named-checkconf                              # 1. config syntax
sudo named-checkzone example.com /etc/bind/zones/db.example.com   # 2. zone syntax
sudo systemctl status bind9                       # 3. is it running?
sudo journalctl -u bind9 -n 100 --no-pager        # 4. last 100 log lines
dig @127.0.0.1 example.com SOA +short             # 5. does it answer?
dig @127.0.0.1 example.com AXFR                   # 6. do transfers work?
sudo ss -ltnup sport = :53                        # 7. is port 53 bound?
```

---

## Sources

- *Linux Network Administrator's Guide, 2nd Edition* — Olaf Kirch & Terry Dawson (O'Reilly, 2000), Chapter 6, "Name Service and Resolver Configuration", specifically the sections *The host.conf File*, *The nsswitch.conf File*, *Configuring Name Server Lookups Using resolv.conf*, *How DNS Works*, *Types of Name Servers*, *Running named*, *The named.boot File*, *The BIND 8 named.conf File*, *Writing the Master Files*, and *Verifying the Name Server Setup*.
- *Ubuntu Server Guide* (Ubuntu 20.04 LTS, Canonical, 2020), *Domain Name Service (DNS)* chapter: installation (`apt install bind9`), `/etc/bind/` layout, `named.conf.options`, `named.conf.local`, `named.conf.default-zones`, caching nameserver configuration, primary server configuration, secondary server configuration, `named-checkzone`, `rndc querylog`, and the *Logging* subsection describing channels and categories.
- Modern updates (BIND 9.18+, systemd integration, AppArmor confinement, `tsig-keygen`, DNSSEC `dnssec-validation auto`) sourced from the upstream BIND 9 ARM (Administrator Reference Manual), the manpages shipped with the Debian `bind9-doc` package, and the Debian `bind9` package maintainer scripts.
