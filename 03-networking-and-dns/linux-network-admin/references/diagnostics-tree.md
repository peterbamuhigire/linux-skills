# Network Diagnostics Decision Tree

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Symptom-first decision tree for diagnosing network problems on an
Ubuntu/Debian server. Read this whenever a user reports "the server is
down", "I can't reach it", "the app can't talk to the database", or "DNS is
broken". Start at the matching symptom, run the commands in order, and
follow the branches until you hit a concrete fix. Every command here is the
modern form (`ip`, `ss`, `resolvectl`, `mtr`) — translated from the legacy
`ifconfig` / `netstat` / `route` tools the older books still use.

## Table of contents

- [Starting rules](#starting-rules)
- [The 30-second snapshot](#the-30-second-snapshot)
- [Symptom: can't reach the internet](#symptom-cant-reach-the-internet)
- [Symptom: DNS resolution fails](#symptom-dns-resolution-fails)
- [Symptom: reaches some hosts, not others](#symptom-reaches-some-hosts-not-others)
- [Symptom: slow or unstable](#symptom-slow-or-unstable)
- [Symptom: packet loss](#symptom-packet-loss)
- [Symptom: a specific port is refused or times out](#symptom-a-specific-port-is-refused-or-times-out)
- [Symptom: interface flaps or won't come up](#symptom-interface-flaps-or-wont-come-up)
- [Symptom: netplan apply killed the SSH session](#symptom-netplan-apply-killed-the-ssh-session)
- [Reading common outputs](#reading-common-outputs)
- [Sources](#sources)

## Starting rules

1. **Diagnose from the server itself.** Your laptop's resolver cache, VPN,
   proxy, and DNS search list will lie. SSH in, then test.
2. **Change one variable at a time.** If you flip three things between
   tests, you will not know which fix worked.
3. **Work the stack bottom-up.** Link → IP → route → DNS → port → app. Do
   not debug the app until packets are proven to reach it.
4. **Never edit `/etc/resolv.conf` by hand.** It is a symlink to
   `/run/systemd/resolve/stub-resolv.conf`. Fix DNS in netplan or
   `/etc/systemd/resolved.conf`.
5. **Prefer `netplan try` when fixing remotely.** The 120-second rollback
   is the difference between a quick retry and a console session at 2 am.

## The 30-second snapshot

Run this block *before* branching into a specific symptom — it answers
"what does the server think its network looks like right now?"

```bash
ip -brief link
ip -brief addr
ip route show
ip -6 route show
resolvectl status
ss -tulnp
```

What to read:

- **`ip -brief link`** — one line per interface. Columns: name, state
  (`UP`/`DOWN`), MAC. `DOWN` or `NO-CARRIER` on the data interface = layer-1
  problem, stop here.
- **`ip -brief addr`** — same list plus IPv4/IPv6 addresses. Missing
  expected address = config did not apply.
- **`ip route show`** — must contain `default via <gw> dev <iface>`. No
  default route = no internet.
- **`resolvectl status`** — DNS per link. Empty `DNS Servers:` = DNS is
  broken.
- **`ss -tulnp`** — listening TCP/UDP sockets. Confirms which services are
  bound and to which address (`0.0.0.0`, `127.0.0.1`, a specific IP).

If this snapshot looks normal, the problem is *outside* the server — the
switch, the gateway, the upstream firewall, or the remote host.

## Symptom: can't reach the internet

User report: "curl times out", "apt update fails", "nothing from this box
reaches the outside".

### Step 1 — Is the link up?

```bash
ip -brief link
```

- `UP` → go to Step 2.
- `DOWN` → `sudo ip link set dev <iface> up`. Flaps back to `DOWN` or
  `NO-CARRIER` = dead cable/port/SFP. Check physical, then `ethtool <iface>`.
- No such device → the name in `/etc/netplan/*.yaml` does not match the
  kernel name. Fix the YAML.

### Step 2 — Does it have an address?

```bash
ip -brief addr
```

- No IPv4 → DHCP failed or static did not apply.
  - DHCP: `journalctl -u systemd-networkd -n 50` and look for
    DHCPDISCOVER/DHCPOFFER. No OFFER = DHCP server not reachable (bad VLAN,
    wrong switchport).
  - Static: `sudo netplan generate && sudo netplan apply`. A YAML error
    anywhere in `/etc/netplan/` silently skips the whole config.
- Link-local `169.254.x.x` → DHCP failed, kernel auto-assigned. Same fix.

### Step 3 — Is there a default route?

```bash
ip route show
```

- Missing `default via ...` → add `routes: - to: default, via: <gw>` in
  netplan and `sudo netplan try`.
- Two default routes, equal metric → one silently loses; differentiate
  metrics.

### Step 4 — Does the kernel pick a sane route to 8.8.8.8?

```bash
ip route get 8.8.8.8
```

Expected: `8.8.8.8 via 192.168.1.1 dev eth0 src 192.168.1.50`.

- `Network is unreachable` → default route missing or gateway not on any
  configured subnet.
- Wrong `src` / wrong `dev` → policy routing misconfigured or metrics
  inverted. Check `ip rule show` and the `routes:` blocks.

### Step 5 — Can you ping the gateway?

```bash
ping -c 3 -W 2 $(ip route show default | awk '/default/ {print $3}')
```

- Replies → L2 is fine, go to Step 6.
- 100% loss → gateway unreachable. `ip neigh show` — a `FAILED` entry for
  the gateway confirms ARP is not resolving. Check cable, switch, gateway.

### Step 6 — Can you ping a public IP (DNS-free)?

```bash
ping -c 3 -W 2 1.1.1.1
```

- Replies → routing works, problem is DNS → jump to "DNS resolution fails".
- 100% loss → routing past the gateway is broken. `mtr -n 1.1.1.1` to find
  the hop that drops packets.

### Step 7 — Resolve a name

```bash
resolvectl query example.com
```

- Returns an IP → full stack works. The "no internet" report is about a
  specific site or port; jump to "a specific port is refused".
- `Temporary failure` / `unknown host` → jump to "DNS resolution fails".

## Symptom: DNS resolution fails

User report: "curl: could not resolve host", "ping google.com says unknown
host", "apt update hangs on DNS".

### Step 1 — What does systemd-resolved know?

```bash
resolvectl status
```

Read the per-link sections:

```
Link 2 (eth0)
  Current Scopes: DNS
DefaultRoute setting: yes
       DNS Servers: 1.1.1.1 8.8.8.8
        DNS Domain: lan
```

- Empty `DNS Servers:` → no resolvers on that link. Fix
  `nameservers.addresses` in netplan.
- Old values still present → netplan didn't re-apply. `sudo netplan apply`.
- `DefaultRoute setting: no` on the only uplink → link won't be used for
  global DNS. Either install a default route on that link, or
  `resolvectl default-route eth0 yes`.

### Step 2 — Query the local stub and a direct upstream

```bash
resolvectl query example.com
dig @127.0.0.53 example.com
dig @1.1.1.1 example.com +time=3 +tries=1
```

- Local stub succeeds → the stack works. A complaining app has its own
  resolver cache (node, JVM, docker). Fix there.
- Stub fails, upstream works → restart `systemd-resolved`. Still broken?
  Check `/etc/systemd/resolved.conf` for bad `DNS=` / `Domains=` /
  `DNSSEC=`. Try `DNSSEC=no` temporarily — some upstreams do not serve
  validated answers and `DNSSEC=yes` causes SERVFAIL.
- Both fail → the server cannot reach the internet. Go back to "can't
  reach the internet" from Step 5.

### Step 3 — Resolver logs

```bash
journalctl -u systemd-resolved -n 50 --no-pager
```

Look for:

- `DNSSEC validation failed` → set `DNSSEC=allow-downgrade`.
- `SERVFAIL` → upstream resolver is broken or censoring; pick another.
- `using degraded feature set` → resolved fell back because the upstream
  lacks modern features. Usually harmless.

## Symptom: reaches some hosts, not others

User report: "I can ping Google but not our internal DB" (or vice versa).

### Step 1 — Split-horizon DNS

```bash
resolvectl query db.internal
dig @1.1.1.1 db.internal
dig @127.0.0.53 db.internal
```

Different answers from internal vs public resolver → split-horizon. The
server must use the internal resolver to see the private zone. Fix
`nameservers.addresses` in netplan.

### Step 2 — Route to the destination

```bash
ip route get 10.20.30.40
```

- `unreachable` → no route. Add `routes: - to: 10.20.0.0/16, via:
  10.10.10.254` in netplan.

### Step 3 — Can you reach it?

```bash
mtr -n -c 20 10.20.30.40
```

- All hops clean → routing is fine; remote side is dropping (their
  firewall, their service). Escalate.
- Loss starts at hop N → that device is the problem. Hop 1 = your gateway
  (local); hop >1 = someone else's gear.

### Step 4 — Local firewall silently dropping outbound?

```bash
sudo ufw status verbose
sudo iptables -S OUTPUT
sudo nft list ruleset 2>/dev/null | head -60
```

Look for `OUTPUT ... DROP` or `chain output { policy drop; }`. UFW defaults
allow outbound, but a hardened host may be different.

## Symptom: slow or unstable

### Step 1 — Latency and jitter

```bash
mtr -n -c 30 <target>
```

- `Loss% > 1` only on the final hop → the remote drops, not you.
- `Loss% > 1` starting mid-path → that hop is rate-limiting ICMP; look at
  the *final* hop to judge reality. Mid-path ICMP loss is often cosmetic.
- `StDev` close to `Avg` → jitter as large as latency. Wifi or congested
  upstream.

### Step 2 — Is the NIC negotiating correctly?

```bash
sudo ethtool eth0 | grep -E 'Speed|Duplex|Link detected'
```

- `Speed: 100Mb/s` on a gigabit link or `Duplex: Half` on any fast link =
  auto-negotiation failed. Check cable, switch port, SFP.

### Step 3 — RX/TX errors and drops

```bash
ip -s link show eth0
```

- Non-zero `errors` / `overrun` → hardware or cable fault.
- `dropped` climbing on RX → kernel can't keep up; raise
  `net.core.netdev_max_backlog`, check NIC offloads.

### Step 4 — PMTU discovery

```bash
ping -c 3 -M do -s 1472 1.1.1.1
```

- Succeeds → PMTU >= 1500.
- `Frag needed and DF set` → try `-s 1420`, then `-s 1400`. PPPoE paths are
  1492; IPsec/GRE tunnels 1400-1420. Fix: set `mtu: 1420` on the offender
  in netplan, or `net.ipv4.tcp_mtu_probing=1`.

## Symptom: packet loss

### Step 1 — Rule out ICMP rate-limiting

```bash
mtr -n -c 100 <target>
mtr -n -T -P 443 -c 100 <target>
```

ICMP shows loss but TCP does not = mid-path ICMP rate-limit, harmless.

### Step 2 — Watch counters over time

```bash
watch -n 1 'ip -s link show eth0 | tail -4'
```

Look for RX `dropped` / `errors` climbing.

### Step 3 — Conntrack (NAT gateways)

```bash
sudo sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max
```

`count` close to `max` → table full, new connections dropped. Raise
`nf_conntrack_max` in sysctl.

### Step 4 — Capture and eyeball

```bash
sudo tcpdump -ni eth0 -c 200 'host <target>'
```

Look for retransmits (repeated seq), RSTs, zero-window announcements.

## Symptom: a specific port is refused or times out

User report: "I can't connect to port 5432 on db.internal".

### Step 1 — DNS right?

```bash
resolvectl query db.internal
```

### Step 2 — Port open on the remote?

```bash
timeout 3 bash -c '</dev/tcp/db.internal/5432' && echo OPEN || echo CLOSED
# or:
nc -zv db.internal 5432
```

- `OPEN` → the network path is fine; problem is application-level
  (credentials, TLS, wrong db).
- `CLOSED` fast → remote actively refused (service not listening, or
  firewall RSTs).
- `CLOSED` after timeout → silent drop. Firewall in the middle.
  `mtr -n -T -P 5432 db.internal` to find where.

### Step 3 — Is *this* server listening (for an inbound complaint)?

```bash
sudo ss -tulnp | grep :5432
```

- Bound to `127.0.0.1:5432` but clients come from elsewhere → loopback-only
  bind. Fix in service config (e.g. PostgreSQL `listen_addresses = '*'`).
- Bound to the right address but remote still fails → local firewall
  blocking. `sudo ufw status` and allow.
- Nothing listening → service down. `systemctl status <service>`.

## Symptom: interface flaps or won't come up

```bash
sudo dmesg -T | grep -i -E 'eth|link|nic' | tail -30
networkctl status eth0
journalctl -u systemd-networkd -n 50 --no-pager
sudo ethtool eth0
cat /sys/class/net/eth0/carrier
```

- `Link is Down` / `carrier = 0` → physical. Cable, SFP, switch port.
- `carrier = 1` but `networkctl` says `failed` / `configuring` → netplan or
  networkd unit problem, read the journal for the reason.

## Symptom: netplan apply killed the SSH session

1. Get a console (KVM, IPMI, hosting web console, physical).
2. `sudo journalctl -u systemd-networkd -n 100` — what happened at apply.
3. `ip -brief addr && ip route show` — see the new reality.
4. If the default route is missing or wrong, fix `/etc/netplan/*.yaml` and
   `sudo netplan apply` again.
5. For every future remote change, always use `sudo netplan try --timeout
   120` — the rollback repairs bad configs after 2 minutes.

## Reading common outputs

**`ip -brief addr`** — `UNKNOWN` on `lo` is normal; any data NIC must be
`UP`. Missing expected address = config did not apply.

**`ip route show`** — exactly one `default` line per address family unless
intentionally multi-homed.

**`resolvectl status`** — the per-link block is what matters; empty
`DNS Servers:` = DNS not configured on that link.

**`ss -tulnp`** flags: `-t` TCP, `-u` UDP, `-l` listen, `-n` numeric, `-p`
process. `0.0.0.0`/`::` = all addresses; `127.0.0.1` = loopback-only (the
classic "why can no one else connect" trap).

**`ping -c 3`**: `time=` rising = congestion/bufferbloat; `ttl=` much lower
than expected = unusual extra hops; `Destination Host Unreachable` =
gateway has no route or ARP failed; `Destination Net Unreachable` = no
route upstream.

**`mtr -n -c 20`**: loss on a middle hop that disappears on later hops =
ICMP rate-limit, ignore. Loss that persists from hop N to the end = real
problem at hop N.

**`journalctl -u systemd-networkd -u systemd-resolved`** — grep for:
`DHCPv4 address` (DHCP got it), `Gained carrier` / `Lost carrier`
(physical events), `Could not resolve` (resolver failed), `DNSSEC
validation failed` (set `DNSSEC=allow-downgrade`), `Failed to start`
(service not running).

**`nmcli device status`** — only relevant if `renderer: NetworkManager`.
With `renderer: networkd` it reports nothing — use `networkctl` instead.

## Sources

- *Linux Network Administrator's Guide, 2nd Edition* (O'Reilly) — Chapter 5
  "Configuring TCP/IP Networking" (ping, route verification,
  troubleshooting flow — legacy `ifconfig`/`route`/`netstat` translated to
  `ip`/`ss`).
- *Linux Network Administrator's Guide* — Chapter 6 "Name Service and
  Resolver Configuration" (resolver debugging, translated to `resolvectl`
  and `dig`).
- *Ubuntu Server Guide* (Canonical, Focal 20.04 LTS) — "Network
  Configuration" chapter: `ip` command usage, systemd-resolved behaviour,
  `/etc/resolv.conf` symlink.
- *Mastering Ubuntu* (Ghada Atef, 2023) — section V.III "Troubleshooting
  common issues and errors".
