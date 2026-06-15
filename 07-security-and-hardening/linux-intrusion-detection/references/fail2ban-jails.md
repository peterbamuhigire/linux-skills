# fail2ban Jail Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Complete fail2ban reference for Ubuntu/Debian servers running Nginx,
Apache, Postfix, Dovecot, MySQL, SSH, and common web apps. Covers
architecture (filters, actions, jails), the precedence rules between
`jail.conf` and `jail.local`, a full jail library you can drop in,
writing custom filters with regex, unbanning workflow, and the log
patterns that tell you whether fail2ban is actually doing its job.
Everything here assumes fail2ban ≥ 0.11 (Ubuntu 22.04 ships 0.11.2).

## Table of contents

- [Architecture: filters, actions, jails](#architecture-filters-actions-jails)
- [Configuration precedence](#configuration-precedence)
- [Global defaults: jail.local](#global-defaults-jaillocal)
- [Jail library](#jail-library)
- [Writing custom filters](#writing-custom-filters)
- [Actions beyond the firewall](#actions-beyond-the-firewall)
- [Tuning bantime, findtime, maxretry](#tuning-bantime-findtime-maxretry)
- [Reading /var/log/fail2ban.log](#reading-varlogfail2banlog)
- [Unbanning workflow](#unbanning-workflow)
- [Operations cheat sheet](#operations-cheat-sheet)
- [Sources](#sources)

## Architecture: filters, actions, jails

fail2ban is three things working together:

**Filter** — a regex that knows what a "failure" looks like in a log
file. Lives in `/etc/fail2ban/filter.d/<name>.conf`. Each filter
extracts the offending IP via the `<HOST>` placeholder.

**Action** — what to do when the filter trips enough times. Lives in
`/etc/fail2ban/action.d/<name>.conf`. Typical actions: add an iptables
DROP rule, send an email, add a route blackhole, hit an API.

**Jail** — a filter + an action + a log file + counters
(`maxretry`, `findtime`, `bantime`). Lives in
`/etc/fail2ban/jail.d/<name>.conf` or inside `jail.local`. A jail is
the unit of operation — you enable, disable, and query jails.

The flow:

```
log line -> filter regex -> match? -> counter++ -> threshold? -> action -> ban
```

The daemon watches every enabled jail's log file, applies the filter,
and when an IP crosses `maxretry` failures within `findtime` seconds it
runs the ban action for `bantime` seconds. After `bantime`, the unban
action runs automatically.

## Configuration precedence

Files are loaded in this order (later overrides earlier):

1. `/etc/fail2ban/jail.conf`            — distro defaults. **Never edit.**
2. `/etc/fail2ban/jail.d/*.conf`        — per-purpose drop-ins.
3. `/etc/fail2ban/jail.local`           — site-wide overrides.
4. `/etc/fail2ban/jail.d/*.local`       — per-purpose overrides.

Convention: keep your hardening in `jail.local`; if you need to split,
put each jail's overrides in `jail.d/<service>.local`. Leaving
`jail.conf` untouched means `apt upgrade` never clobbers your policy.

The same pattern applies to filters and actions: `*.conf` is distro,
`*.local` is yours.

## Global defaults: jail.local

Start with this skeleton. Every jail below inherits from `[DEFAULT]`
unless it overrides a value explicitly.

```ini
# /etc/fail2ban/jail.local
[DEFAULT]
# What NOT to ban
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 192.168.0.0/16

# How fail2ban enforces
banaction       = ufw
banaction_allports = ufw
backend         = systemd

# Counters
bantime   = 1h
findtime  = 10m
maxretry  = 5

# Exponential backoff for repeat offenders
bantime.increment = true
bantime.factor    = 2
bantime.maxtime   = 1w

# Email settings (if you want alerts)
destemail = admin@example.com
sender    = fail2ban@example.com
mta       = sendmail
action    = %(action_)s
```

Notes:

- `backend = systemd` reads from the systemd journal, which is what
  modern Ubuntu logs into. It's faster and catches services that don't
  write text logs. Individual jails can override with a path.
- `banaction = ufw` uses the UFW helper — cleaner than the raw iptables
  action on an Ubuntu box that already runs UFW.
- `bantime.increment = true` makes repeat offenders climb the ladder:
  1h → 2h → 4h → 8h → … up to `maxtime`. This alone dramatically
  reduces ban churn.
- `ignoreip` should include your office, your VPN, the monitoring
  system, and any load balancer CIDR. **Never ignore 0.0.0.0/0.**

## Jail library

Drop each of these into `jail.local` (or into `jail.d/<name>.local`).
Enable what applies to your stack and leave the rest off.

### sshd

```ini
[sshd]
enabled  = true
port     = ssh
backend  = systemd
maxretry = 4
bantime  = 1h
findtime = 10m
```

The default filter `sshd` already catches "Failed password",
"Invalid user", "Did not receive identification string", and the
common pubkey permission errors. The systemd backend catches all of
those even if you have rsyslog off.

### apache-auth — HTTP basic auth brute force

```ini
[apache-auth]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/error.log
maxretry = 5
bantime  = 30m
```

Matches `[authz_core:error] ... AH0133x: user <user>: password mismatch`
and similar.

### apache-badbots — malicious user-agents

```ini
[apache-badbots]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/access.log
bantime  = 2d
maxretry = 1
```

The shipped filter has a long regex of known bad bots. Works equally
well against Nginx access logs if you point `logpath` there — but use
`nginx-botsearch` (below) on Nginx hosts.

### apache-noscript

```ini
[apache-noscript]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/access.log
maxretry = 6
bantime  = 1h
```

Bans IPs hammering CGI/script paths that don't exist — a signal of
automated vulnerability scanning.

### apache-overflows

```ini
[apache-overflows]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/error.log
maxretry = 2
bantime  = 1d
```

Matches oversized request lines that look like buffer-overflow probes.

### nginx-http-auth — basic auth + limit_req rejects

```ini
[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log
maxretry = 5
bantime  = 1h
```

Default filter catches `user "x": password mismatch` and `no user/password
was provided`. Pair with `auth_basic` on your admin URLs.

### nginx-limit-req — rate-limit abuse

```ini
[nginx-limit-req]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log
maxretry = 10
findtime = 10m
bantime  = 1h
```

Fires when your Nginx `limit_req` zone rejects a client repeatedly.
Depends on having `limit_req_zone` configured in nginx.conf:

```nginx
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
server {
    location /api/ {
        limit_req zone=api burst=20 nodelay;
    }
}
```

### nginx-botsearch — scanner probes

```ini
[nginx-botsearch]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 2
bantime  = 1d
```

Bans IPs probing `/wp-login.php`, `/xmlrpc.php`, `/.env`, `/.git/`,
`/phpmyadmin/`, `/admin/`, and similar common paths on hosts that don't
serve them.

### postfix — mail relay abuse

```ini
[postfix]
enabled  = true
port     = smtp,ssmtp,submission
filter   = postfix[mode=aggressive]
logpath  = /var/log/mail.log
maxretry = 5
bantime  = 1h
```

The `aggressive` mode bans on `RELAY_DENIED`, `SASL auth failed`, and
HELO/EHLO hostname mismatches.

### dovecot — IMAP/POP3 brute force

```ini
[dovecot]
enabled  = true
port     = pop3,pop3s,imap,imaps,submission,465,sieve
logpath  = /var/log/mail.log
maxretry = 5
bantime  = 1h
```

### recidive — repeat offenders across jails

```ini
[recidive]
enabled  = true
logpath  = /var/log/fail2ban.log
bantime  = 30d
findtime = 1d
maxretry = 3
action   = %(action_mwl)s
```

Watches fail2ban's own log. If an IP gets banned by *any* jail 3 times
in 24 hours, it earns a 30-day ban. The single most effective jail you
can enable — it turns noisy script kiddies into silence.

### wordpress (custom)

```ini
[wordpress-hard]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 2
bantime  = 1d
filter   = wordpress-hard
```

Filter file at `/etc/fail2ban/filter.d/wordpress-hard.conf`:

```ini
[Definition]
failregex = ^<HOST> .* "(POST|GET) /wp-login\.php
            ^<HOST> .* "(POST) /xmlrpc\.php
ignoreregex =
```

### phpmyadmin-syslog

```ini
[phpmyadmin-syslog]
enabled  = true
port     = http,https
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 1d
```

The default filter catches `phpMyAdmin: user denied: <user> (mysql-denied)`
messages. Assumes you route phpMyAdmin auth through system syslog.

## Writing custom filters

A filter is a tiny ini file with one mandatory key: `failregex`. Use
`<HOST>` wherever an IP address appears — fail2ban expands it to a
regex that captures the IP.

### Example: ban IPs that POST to /api/login too much

`/etc/fail2ban/filter.d/myapp-login.conf`:

```ini
[Definition]
failregex = ^<HOST> -.*"POST /api/login HTTP/[0-9.]+" (4[0-9]{2}|5[0-9]{2})
ignoreregex =
```

Corresponding jail:

```ini
[myapp-login]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 10
findtime = 5m
bantime  = 1h
filter   = myapp-login
```

### Test the filter against a real log before enabling

```bash
sudo fail2ban-regex /var/log/nginx/access.log \
    /etc/fail2ban/filter.d/myapp-login.conf
```

Output will show `Matched` and `Lines` counts per regex. Zero matches
= your regex is wrong. Too many matches = you'll ban legitimate users.

### Useful filter building blocks

- `<HOST>` — captures IPv4 or IPv6.
- `<ADDR>` — captures only the IP (no brackets for IPv6).
- Escape literal dots in URL paths: `/api/login` → `/api/login` works,
  but `/api/v1.2/` must be `/api/v1\.2/`.
- Use non-capturing groups `(?:...)` to keep the capture clean.
- Add `^` at the start — fail2ban reads the log with `datepattern`
  already stripped, so `^<HOST>` is usually right.
- Always include a timestamp pattern the log actually has, via
  `datepattern`:

```ini
[Definition]
datepattern = {^LN-BEG}%%Y-%%m-%%dT%%H:%%M:%%S
failregex = ^<HOST> ...
```

### Multi-line filters

For logs where the failure spans several lines (mostly mail), add:

```ini
[Definition]
maxlines = 10
```

and write a regex that includes line breaks with `\n`.

## Actions beyond the firewall

fail2ban ships with many actions in `/etc/fail2ban/action.d/`. Common
ones:

| Action          | Effect                                               |
|-----------------|------------------------------------------------------|
| `ufw`           | `ufw insert 1 deny from <ip>` (preferred on Ubuntu)  |
| `iptables-allports` | DROP all ports for the IP                        |
| `iptables-multiport`| DROP the specific ports the jail covers           |
| `nftables`      | nftables set add                                     |
| `route`         | Add null-route so kernel drops silently              |
| `mail-whois`    | Send email with `whois` lookup of the offender       |
| `mail-whois-lines`| Email with whois + log lines that triggered the ban|
| `abuseipdb`     | Report to AbuseIPDB (needs API key)                  |
| `shorewall`     | For Shorewall users                                  |

Assemble a jail action stack via the magic names in `jail.conf`:

```ini
action_  = %(banaction)s[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
action_mw = %(action_)s
            %(mta)s-whois[name=%(__name__)s, sender="%(sender)s", dest="%(destemail)s", protocol="%(protocol)s", chain="%(chain)s"]
action_mwl = %(action_)s
             %(mta)s-whois-lines[name=%(__name__)s, sender="%(sender)s", dest="%(destemail)s", logpath="%(logpath)s", chain="%(chain)s"]
```

Then in your jail:

```ini
[sshd]
action = %(action_mwl)s
```

sends email with whois and log lines on each ban.

### Custom script action

You can run an arbitrary script:

```ini
# /etc/fail2ban/action.d/ping-slack.local
[Definition]
actionban = /usr/local/bin/slack-alert.sh "<name>: banned <ip> (failures: <failures>)"
actionunban = /usr/local/bin/slack-alert.sh "<name>: unbanned <ip>"
```

Reference it in a jail:

```ini
action = %(action_)s
         ping-slack
```

## Tuning bantime, findtime, maxretry

| Setting  | What it does                                                   |
|----------|----------------------------------------------------------------|
| `maxretry`| Allowed failures in `findtime` before ban                     |
| `findtime`| Rolling window for counting failures                          |
| `bantime` | How long the ban lasts                                        |

### Sensible starting points

| Service                  | maxretry | findtime | bantime |
|--------------------------|----------|----------|---------|
| sshd (public)            | 4        | 10m      | 1h      |
| sshd (internal, internal users only) | 8 | 10m  | 30m     |
| nginx-http-auth (admin)  | 5        | 10m      | 1h      |
| nginx-botsearch          | 2        | 5m       | 1d      |
| wordpress-hard           | 2        | 5m       | 1d      |
| apache-badbots           | 1        | 1m       | 2d      |
| postfix                  | 5        | 10m      | 1h      |
| recidive                 | 3        | 1d       | 30d     |

### How to tune

1. Enable the jail with defaults.
2. Watch `/var/log/fail2ban.log` for 48 hours under normal traffic.
3. If you see false positives (legit users getting banned), raise
   `maxretry` or shorten `findtime`.
4. If you see the same IP banned every hour, raise `bantime` for that
   jail or make sure `recidive` is enabled.
5. Turn on `bantime.increment` if you haven't — exponential backoff
   catches persistent attackers without widening your safe window.

## Reading /var/log/fail2ban.log

The log is chatty but very structured. Common lines:

```
2026-04-10 12:34:56,789 fail2ban.filter   [1234]: INFO  [sshd] Found 203.0.113.10 - 2026-04-10 12:34:56
2026-04-10 12:35:01,234 fail2ban.actions  [1234]: NOTICE [sshd] Ban 203.0.113.10
2026-04-10 13:35:01,234 fail2ban.actions  [1234]: NOTICE [sshd] Unban 203.0.113.10
```

Useful queries:

```bash
# Most-banned IPs (top offenders)
sudo awk '/Ban /{print $(NF)}' /var/log/fail2ban.log | sort | uniq -c | sort -rn | head

# Bans by jail today
sudo grep "$(date +%Y-%m-%d)" /var/log/fail2ban.log | \
    awk '/Ban /{match($0,/\[([a-z0-9-]+)\]/,a); print a[1]}' | sort | uniq -c | sort -rn

# Watch live
sudo tail -F /var/log/fail2ban.log | grep -E 'Ban|Unban|Found'

# Last 10 bans with jail + IP
sudo grep 'Ban ' /var/log/fail2ban.log | tail -10
```

If the log shows `Found` but no `Ban`, `maxretry` hasn't been reached
yet. If you see nothing at all, the filter isn't matching — go back to
`fail2ban-regex`.

## Unbanning workflow

Unbanning is common — you've banned yourself, an ops person typed the
wrong SSH port five times, etc. Three ways to get out:

### 1. Unban via fail2ban-client (the clean way)

```bash
# One IP
sudo fail2ban-client set sshd unbanip 203.0.113.10

# Unban from all jails
sudo fail2ban-client unban 203.0.113.10
```

### 2. Check what's banned right now

```bash
sudo fail2ban-client status                   # all jails
sudo fail2ban-client status sshd              # one jail
sudo fail2ban-client get sshd banip            # IP list
```

### 3. Whitelist for next time

If the same person keeps getting banned, add them to `ignoreip`:

```bash
sudo sed -i 's|^ignoreip = .*|ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 198.51.100.0/24|' /etc/fail2ban/jail.local
sudo systemctl reload fail2ban
```

### 4. I locked myself out of SSH

If SSH itself is blocked and the cloud console is your only way in:

```bash
# From the console:
sudo iptables -D f2b-sshd -s YOUR_IP -j REJECT       # or DROP
sudo ufw delete deny from YOUR_IP
# Then re-add YOUR_IP to ignoreip permanently
```

## Operations cheat sheet

```bash
# Status
sudo systemctl status fail2ban
sudo fail2ban-client status
sudo fail2ban-client status sshd

# Reload after config change
sudo fail2ban-client reload                  # reload all
sudo fail2ban-client reload sshd             # reload one jail

# Test a filter against a real log
sudo fail2ban-regex /var/log/auth.log /etc/fail2ban/filter.d/sshd.conf
sudo fail2ban-regex /var/log/nginx/access.log /etc/fail2ban/filter.d/wordpress-hard.conf

# Check which jails will start on boot
sudo fail2ban-client -d 2>/dev/null | grep -E '^set .* enabled true' | head

# Live log
sudo tail -F /var/log/fail2ban.log

# Restart from scratch if state is confused
sudo systemctl stop fail2ban
sudo rm -f /var/lib/fail2ban/fail2ban.sqlite3
sudo systemctl start fail2ban
```

## Optional fast path

`sudo sk-fail2ban-status` (when the `sk-*` scripts are installed)
prints a condensed status: jails, active bans, total bans per jail,
and recent bans with rough geolocation hints. It wraps the commands in
this file.

## Sources

- *Mastering Linux Security and Hardening*, Donald A. Tevault, 3rd
  Edition, Packt — Chapter 14 "Vulnerability Scanning and Intrusion
  Detection": installing, configuring, and tuning fail2ban; writing
  filters and actions.
- *Practical Linux Security Cookbook*, Tajinder Kalsi, Packt — fail2ban
  recipes for SSH, Apache, and mail services; log monitoring patterns.
- *Ubuntu Server Guide*, Canonical — "Security / fail2ban" section and
  referenced firewall chapter.
- fail2ban upstream docs: https://github.com/fail2ban/fail2ban/wiki
- Manual pages: `fail2ban-client(1)`, `fail2ban-regex(1)`, `jail.conf(5)`.
