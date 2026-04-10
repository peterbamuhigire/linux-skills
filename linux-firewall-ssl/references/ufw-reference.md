# UFW Firewall Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

UFW (Uncomplicated Firewall) is Ubuntu's default host firewall. It is a
command-line front end to the kernel packet filter — `iptables` on Ubuntu
20.04 and `nftables` on 22.04+ — designed for people who want a firewall that
works without reading 200 pages of iptables tutorial. This reference covers
every command, every config file, and six complete server profiles you can
copy verbatim.

## Table of contents

- [Architecture — how UFW reaches the kernel](#architecture--how-ufw-reaches-the-kernel)
- [Lifecycle commands (enable, disable, reset, status)](#lifecycle-commands-enable-disable-reset-status)
- [Default policies](#default-policies)
- [Rule syntax cheat sheet](#rule-syntax-cheat-sheet)
- [Allow, deny, reject, limit](#allow-deny-reject-limit)
- [Rate limiting — what UFW's limit actually does](#rate-limiting--what-ufws-limit-actually-does)
- [Source, destination, interface, direction](#source-destination-interface-direction)
- [Application profiles (/etc/ufw/applications.d/)](#application-profiles-etcufwapplicationsd)
- [Rule deletion, ordering, and insertion](#rule-deletion-ordering-and-insertion)
- [Logging](#logging)
- [Advanced rules: /etc/ufw/before.rules](#advanced-rules-etcufwbeforerules)
- [IPv6](#ipv6)
- [Inspecting the underlying kernel rules](#inspecting-the-underlying-kernel-rules)
- [Worked profile 1: public web server](#worked-profile-1-public-web-server)
- [Worked profile 2: bastion / jump host](#worked-profile-2-bastion--jump-host)
- [Worked profile 3: database server (private)](#worked-profile-3-database-server-private)
- [Worked profile 4: mail server](#worked-profile-4-mail-server)
- [Worked profile 5: monitoring host (Prometheus scrape target)](#worked-profile-5-monitoring-host-prometheus-scrape-target)
- [Worked profile 6: reverse proxy in front of apps](#worked-profile-6-reverse-proxy-in-front-of-apps)
- [Troubleshooting checklist](#troubleshooting-checklist)
- [Sources](#sources)

## Architecture — how UFW reaches the kernel

Nothing in UFW actually filters packets. The layers, top to bottom:

```
user → ufw CLI → /etc/ufw/*.rules → ufw-init → iptables-restore (20.04)
                                              └→ nft (22.04+)
                                                 └→ netfilter in the kernel
```

- **CLI.** `/usr/sbin/ufw` is a Python program that parses arguments and
  edits text files under `/etc/ufw/`.
- **Rule files.** `/etc/ufw/user.rules` (IPv4) and `/etc/ufw/user6.rules`
  (IPv6) hold the rules you add with `ufw allow` / `ufw deny`.
- **Framework files.** `/etc/ufw/before.rules`, `/etc/ufw/after.rules`,
  `/etc/ufw/before6.rules`, `/etc/ufw/after6.rules`, and
  `/etc/ufw/sysctl.conf` shape the chains UFW generates. Power users edit
  these; normal users should not.
- **Kernel backend.** On Ubuntu 20.04 UFW writes iptables rules. On 22.04
  and later the backend is `iptables-nft` (nft under the hood, same
  iptables syntax) and the generated table is `filter`. Either way the
  answer to "where are my rules really stored?" is the same: they are
  *regenerated* from `/etc/ufw/*.rules` every time UFW enables or reloads.

Because UFW regenerates rules on enable, **you cannot persist changes with
`iptables-save`**. Always use the `ufw` CLI or edit the framework files.

## Lifecycle commands (enable, disable, reset, status)

```bash
sudo ufw enable                   # turn the firewall on; also enables at boot
sudo ufw disable                  # turn it off; rules are preserved
sudo ufw reload                   # re-read rules after editing before.rules
sudo ufw reset                    # wipe all rules, disable — DANGEROUS
sudo ufw status                   # simple listing
sudo ufw status verbose           # includes default policy, logging level, profiles
sudo ufw status numbered          # numbered rules, used for deletion
sudo ufw version
```

`ufw reset` is destructive. On a remote server, always open an SSH allow
rule **before** enabling the firewall, or you will lock yourself out:

```bash
sudo ufw allow OpenSSH
sudo ufw enable
```

The `OpenSSH` profile is installed by the `ufw` package itself, so it is
always available.

## Default policies

UFW ships with:

- `default deny incoming`
- `default allow outgoing`
- `default deny routed`

This is the correct posture for 99 % of servers. Confirm and reassert:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default deny routed      # unless this box is a router
```

**Incoming default deny** means any packet not explicitly matched by an
allow rule is dropped. **Outgoing default allow** means the server can talk
to anything — convenient, but less strict than a Tight-Egress posture you
might need in regulated environments.

To turn outgoing into a deny-by-default policy you must allow the egress
traffic you actually need first:

```bash
sudo ufw default deny outgoing
sudo ufw allow out 53/udp           # DNS
sudo ufw allow out 53/tcp
sudo ufw allow out 80/tcp           # apt, certbot HTTP-01, OCSP
sudo ufw allow out 443/tcp          # apt, github, etc.
sudo ufw allow out 123/udp          # NTP
sudo ufw allow out to <smtp-host> port 587 proto tcp   # mail relay
```

Tight egress is only worth it if you also monitor blocked-egress log lines —
otherwise an `apt update` will silently hang and you will blame DNS.

## Rule syntax cheat sheet

```
ufw <ACTION> [direction] [log-level] [proto PROTO] \
    [from SRC] [to DST] [port PORT] [app NAME] [comment "text"]
```

All tokens after the action are optional, but order is **significant for
`from`/`to`**. Examples:

```bash
# Terse (port + proto):
sudo ufw allow 443/tcp
sudo ufw allow 53/udp
sudo ufw allow 443             # both tcp and udp

# Full syntax:
sudo ufw allow proto tcp from 10.0.0.0/24 to any port 22
sudo ufw allow in on eth0 to any port 80 proto tcp
sudo ufw allow from 203.0.113.4 to any port 3306 proto tcp comment "prod-app"

# Named port (from /etc/services):
sudo ufw allow ssh
sudo ufw allow http

# App profile:
sudo ufw allow "Nginx Full"
```

## Allow, deny, reject, limit

Four actions define what happens when a packet matches:

| Action | Kernel verdict | Client sees |
|---|---|---|
| `allow` | ACCEPT | connection established |
| `deny` | DROP | hang until timeout |
| `reject` | REJECT with ICMP | immediate `connection refused` |
| `limit` | rate-limited ACCEPT | accepted until flood threshold |

Use `deny` for noisy ports — it wastes scanner time.
Use `reject` when you want a well-behaved client to fail fast (e.g.
inside a trusted LAN).
Use `limit` for SSH.

```bash
sudo ufw deny  23/tcp                        # drop telnet silently
sudo ufw reject 3306/tcp                     # fail fast on internal LAN
sudo ufw limit 22/tcp                        # brute-force protection on SSH
```

## Rate limiting — what UFW's limit actually does

`ufw limit <port>` maps to:

```
ACCEPT if fewer than 6 new connections in the last 30 seconds from this src IP, else DROP
```

It is implemented via the `recent` module (`iptables`) or equivalent
nftables sets. It protects against **single-source** brute force; it does
**not** help against distributed attacks — use Fail2ban for that, on a
cluster use a WAF / cloud rate limiter.

Limits apply per source IP, not globally. Verify:

```bash
sudo ufw status verbose | grep -i limit
# 22/tcp                     LIMIT       Anywhere
```

Do not `limit` HTTP/HTTPS — real browsers open many parallel connections
and will fail at the `recent` threshold. Only limit services where
legitimate clients open one connection at a time (SSH, IMAP, MySQL).

## Source, destination, interface, direction

```bash
# From a specific host:
sudo ufw allow from 203.0.113.4

# From a subnet:
sudo ufw allow from 10.0.0.0/24

# From a subnet to a single port:
sudo ufw allow from 10.0.0.0/24 to any port 5432 proto tcp

# Inbound on a specific interface:
sudo ufw allow in on eth0 to any port 80 proto tcp

# Outbound rule:
sudo ufw allow out on eth0 to any port 443 proto tcp

# Block one bad IP first, then open wide:
sudo ufw deny from 198.51.100.77
sudo ufw allow 80/tcp
```

**Rules are evaluated top-to-bottom, first match wins.** Put narrow `deny`
rules above broad `allow` rules, or use numbered insertion (see below).

## Application profiles (/etc/ufw/applications.d/)

A profile is a small INI file that names a bundle of ports. They live in
`/etc/ufw/applications.d/` and are installed by the package they
represent:

```bash
sudo ufw app list
# Available applications:
#   Apache
#   Apache Full
#   Apache Secure
#   Nginx Full
#   Nginx HTTP
#   Nginx HTTPS
#   OpenSSH
#   Postfix
#   Postfix SMTPS
#   Postfix Submission
```

Inspect:

```bash
sudo ufw app info "Nginx Full"
# Profile: Nginx Full
# Title: Web Server (HTTP,HTTPS)
# Description: Small, but very powerful and efficient web server
# Ports:
#   80,443/tcp
```

Use by name:

```bash
sudo ufw allow "Nginx Full"
sudo ufw allow OpenSSH
sudo ufw allow "Apache Secure"
```

Write your own. Example — `/etc/ufw/applications.d/myapp`:

```ini
[MyApp]
title=My custom app
description=HTTP on 8080, internal
ports=8080/tcp
```

Reload the profile cache:

```bash
sudo ufw app update MyApp
sudo ufw allow MyApp
```

Profiles make audit output readable. After the firewall grows you will
thank yourself.

## Rule deletion, ordering, and insertion

```bash
# Numbered view:
sudo ufw status numbered
#      To                 Action      From
#      --                 ------      ----
# [ 1] 22/tcp             LIMIT IN    Anywhere
# [ 2] 80/tcp             ALLOW IN    Anywhere
# [ 3] 443/tcp            ALLOW IN    Anywhere

# Delete rule 2:
sudo ufw delete 2

# Delete by specification:
sudo ufw delete allow 80/tcp

# Insert a new rule at a position (bumps later rules down):
sudo ufw insert 1 deny from 198.51.100.77
```

Renumbering happens automatically after every `delete`/`insert`. If you
script deletes, always re-run `ufw status numbered` between operations or
delete by specification (`ufw delete allow 80/tcp`) which is stable.

## Logging

```bash
sudo ufw logging on          # default level = low
sudo ufw logging off
sudo ufw logging low         # blocked packets only, rate-limited
sudo ufw logging medium      # blocked + allowed new connections
sudo ufw logging high        # everything (high volume)
sudo ufw logging full        # all packets including allowed ones, no rate limit
```

Logs go to `/var/log/ufw.log` via rsyslog and also to the journal:

```bash
sudo tail -f /var/log/ufw.log
sudo journalctl -kf | grep -i "\[UFW "
```

Each line includes:

```
[UFW BLOCK] IN=eth0 OUT= MAC=... SRC=198.51.100.77 DST=10.0.0.5 LEN=60 TTL=54 PROTO=TCP SPT=55432 DPT=23 WINDOW=29200
```

`SRC=` is the attacker IP, `DPT=` is the port they tried. Stream to an ELK
or Loki instance to build dashboards of blocked traffic.

Leave logging on `low` in production. `medium` or higher fills `/var/log`
on busy servers.

## Advanced rules: /etc/ufw/before.rules

`before.rules` runs before any user rules. Use it for anything UFW's CLI
cannot express:

- Custom chains
- ICMP policy
- Connection marking
- NAT (`/etc/ufw/before.rules` has a `*nat` table)
- Port forwarding with MASQUERADE

Typical additions:

```iptables
# /etc/ufw/before.rules — add above the COMMIT line of the *filter table

# Drop spoofed loopback:
-A ufw-before-input -i lo -j ACCEPT
-A ufw-before-input -d 127.0.0.0/8 ! -i lo -j DROP

# Allow established/related (UFW does this already, shown for clarity):
-A ufw-before-input -m state --state ESTABLISHED,RELATED -j ACCEPT

# Log and drop invalid packets:
-A ufw-before-input -m state --state INVALID -j LOG --log-prefix "[UFW INVALID] "
-A ufw-before-input -m state --state INVALID -j DROP
```

Enable IP forwarding and NAT (for a router/gateway machine):

```bash
# 1) Kernel:
sudo sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/ufw/sysctl.conf

# 2) Policy:
sudo sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

# 3) NAT rules — prepend to /etc/ufw/before.rules:
sudo tee -a /etc/ufw/before.rules >/dev/null <<'EOF'

*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
COMMIT
EOF

# 4) Reload:
sudo ufw reload
```

After editing `before.rules` you **must** run `sudo ufw reload` (or
`disable`/`enable`). Saving the file alone does nothing.

## IPv6

UFW handles IPv6 automatically if `/etc/default/ufw` contains `IPV6=yes`
(default on modern Ubuntu). Every rule you add with `ufw allow 22/tcp` is
installed for both IPv4 and IPv6.

If you need different rules per family, address them in `before.rules`
(IPv4) and `before6.rules` (IPv6), or scope by source address:

```bash
sudo ufw allow from ::/0 to any port 80 proto tcp
sudo ufw allow from 0.0.0.0/0 to any port 80 proto tcp
```

Disabling IPv6 entirely via UFW is done in `/etc/default/ufw`:

```
IPV6=no
```

Reload after editing. Do not disable IPv6 unless you are certain no upstream
(DNS, load balancer, monitoring) expects to reach you over IPv6.

## Inspecting the underlying kernel rules

UFW's `status` output is a summary. The real rules are:

```bash
# 20.04 (iptables-legacy or iptables-nft):
sudo iptables -L -n -v --line-numbers
sudo iptables -t nat -L -n -v
sudo ip6tables -L -n -v

# 22.04+ (nftables backend):
sudo nft list ruleset
sudo nft list table inet filter
```

Read the `ufw-*` chains:

```bash
sudo iptables -S | grep '^-A ufw-user-input'
```

Packet counters show what is actually hitting each rule — useful when
diagnosing "is the firewall eating my traffic?":

```bash
sudo iptables -L INPUT -v -n --line-numbers | head -20
# pkts bytes target  prot opt in  out  source  destination
#  512  29K ufw-before-input  all --  *   *    0.0.0.0/0  0.0.0.0/0
```

Zero counters if you want to benchmark a fresh interval:

```bash
sudo iptables -Z          # zero all counters
```

## Worked profile 1: public web server

Open 22 (rate-limited), 80, 443.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit OpenSSH
sudo ufw allow "Nginx Full"           # 80 + 443
sudo ufw enable
sudo ufw status verbose
```

Expected status:

```
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
22/tcp (OpenSSH)           LIMIT IN    Anywhere
80,443/tcp (Nginx Full)    ALLOW IN    Anywhere
22/tcp (OpenSSH (v6))      LIMIT IN    Anywhere (v6)
80,443/tcp (Nginx Full (v6)) ALLOW IN  Anywhere (v6)
```

## Worked profile 2: bastion / jump host

Only SSH, only from trusted admin IPs. Everything else is closed.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Specific admin IPs (replace with yours):
sudo ufw allow from 203.0.113.4  to any port 22 proto tcp comment "admin-home"
sudo ufw allow from 198.51.100.0/24 to any port 22 proto tcp comment "admin-office"

# Optional: allow SSH from a VPN subnet too
sudo ufw allow from 10.8.0.0/24 to any port 22 proto tcp comment "vpn"

sudo ufw enable
```

Note: no `ufw limit` on SSH here. The source-IP allow list is already the
strongest control; `limit` would throttle legitimate admins typing tmux
commands fast.

## Worked profile 3: database server (private)

MySQL 3306 open only to the application tier, nothing else. Outbound is
limited to patching and the backup destination.

```bash
APP_TIER="10.10.20.0/24"

sudo ufw default deny incoming
sudo ufw default deny outgoing      # tight egress on a DB host

# SSH from admin jumpbox only:
sudo ufw allow from 10.10.99.10 to any port 22 proto tcp comment "jumpbox"

# MySQL from app tier:
sudo ufw allow from $APP_TIER to any port 3306 proto tcp comment "app-tier-mysql"

# Outbound essentials:
sudo ufw allow out 53/udp
sudo ufw allow out 53/tcp
sudo ufw allow out 80/tcp           # apt, certbot
sudo ufw allow out 443/tcp          # apt, backup provider
sudo ufw allow out 123/udp          # NTP

sudo ufw enable
```

Use `reject` instead of `deny` on the MySQL port for non-allowed sources if
you want internal scanners to fail fast — but only inside a trusted LAN;
from the open internet, silent drop is better.

## Worked profile 4: mail server

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw limit OpenSSH

# SMTP (inbound mail from other MTAs)
sudo ufw allow 25/tcp  comment "smtp"

# Submission — authenticated clients sending mail
sudo ufw allow 587/tcp comment "submission"

# SMTPS (deprecated but still widely used)
sudo ufw allow 465/tcp comment "smtps"

# IMAP
sudo ufw allow 143/tcp comment "imap"
sudo ufw allow 993/tcp comment "imaps"

# POP3 (if offered)
sudo ufw allow 110/tcp comment "pop3"
sudo ufw allow 995/tcp comment "pop3s"

# Web admin (roundcube / rainloop) on standard web ports
sudo ufw allow "Nginx Full"

sudo ufw enable
```

Ports explained:

- **25** — MTA-to-MTA delivery. Required if you accept inbound mail.
- **587** — authenticated submission. Required for user mail clients.
- **465** — implicit TLS submission (deprecated by RFC 8314 but still
  common; keep it open if clients need it).
- **143/993** — IMAP plain / IMAPS. 993 is the modern choice.
- **110/995** — POP3 / POP3S. Leave closed unless you have POP users.

Never open 25 without also deploying SPF, DKIM, DMARC — an open relay
test is the first thing attackers run against new mail IPs.

## Worked profile 5: monitoring host (Prometheus scrape target)

A server running `node_exporter` on :9100 should only accept scrapes from
the Prometheus box.

```bash
PROM="10.10.30.5"

sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw limit OpenSSH
sudo ufw allow from $PROM to any port 9100 proto tcp comment "node_exporter"

# Additional exporters if present:
sudo ufw allow from $PROM to any port 9113 proto tcp comment "nginx-exporter"
sudo ufw allow from $PROM to any port 9104 proto tcp comment "mysqld-exporter"

sudo ufw enable
```

Verify the exporter is **only** listening on the right interface. If
`node_exporter` binds `0.0.0.0:9100` the firewall is the last line of
defence; better to bind it to the management network interface too
(`--web.listen-address 10.10.30.42:9100`).

## Worked profile 6: reverse proxy in front of apps

Public Nginx in front of multiple internal app servers.

```bash
INTERNAL="10.0.0.0/16"

sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw limit OpenSSH
sudo ufw allow "Nginx Full"                  # 80+443 from the world
sudo ufw allow from $INTERNAL to any port 9000 proto tcp comment "fpm-upstream"
sudo ufw allow from $INTERNAL to any port 3000 proto tcp comment "node-upstream"

sudo ufw enable
```

On the internal app server side, the mirror rule is:

```bash
PROXY="10.0.0.5"

sudo ufw default deny incoming
sudo ufw allow from $PROXY to any port 9000 proto tcp comment "from-proxy"
sudo ufw allow from 10.0.99.10 to any port 22 proto tcp comment "jumpbox"
sudo ufw enable
```

## Troubleshooting checklist

| Symptom | Diagnose with | Fix |
|---|---|---|
| Locked out after `ufw enable` | Console access | `sudo ufw disable`, add SSH rule, re-enable |
| Rule added but not active | `sudo ufw status verbose` | `sudo ufw reload` |
| Packet dropped unexpectedly | `sudo tail -f /var/log/ufw.log` | Add explicit allow above the deny |
| Service listening but unreachable | `sudo ss -tlnp | grep <port>` | Check both UFW and the service bind address |
| Cloud provider firewall blocking | `curl -v telnet://host:port` | Open port in cloud console too |
| `before.rules` edit ignored | `sudo ufw reload` | Syntax error → `sudo journalctl -u ufw` |
| Rule order wrong, wrong rule wins | `sudo ufw status numbered` | `delete N` then `insert M` |
| IPv6 bypassing rule | `cat /etc/default/ufw` | Ensure `IPV6=yes`, re-add the rule |
| `ufw status` is empty but rules exist | UFW disabled | `sudo ufw enable` |
| Locked out of cloud VM | Use provider's serial console | `ufw disable` from the console |

First-aid command when a firewall change breaks things and you still have
console access:

```bash
sudo ufw disable
# fix
sudo ufw enable
```

## Sources

- Canonical, *Ubuntu Server Guide* (20.04 LTS), "Security → ufw" chapter.
- Ghada Atef, *Mastering Ubuntu* (2023), networking and security chapters.
- `man 8 ufw`, `man 8 ufw-framework`.
- Ubuntu Wiki — <https://wiki.ubuntu.com/UncomplicatedFirewall>.
- netfilter.org — <https://www.netfilter.org/documentation/>.
- nftables wiki — <https://wiki.nftables.org/>.
