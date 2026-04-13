---
name: linux-network-admin
description: Manage Ubuntu/Debian server networking — interfaces, routes, netplan, DNS resolution, NTP, reachability. Handles `ip`, `ss`, `nmcli`, `netplan try/apply`, and diagnostic tooling. Use for any non-firewall, non-mail networking task on a managed server.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---

# Linux Network Administration

## Use when

- Managing interfaces, routes, netplan, DNS resolution, NTP, or reachability from the server side.
- Diagnosing why a host cannot reach another host, port, or resolver.
- Making non-firewall network changes on Ubuntu/Debian servers.

## Do not use when

- The task is firewall policy or TLS; use `linux-firewall-ssl`.
- The task is authoritative DNS service configuration; use `linux-dns-server`.

## Required inputs

- The interface, address, route, VLAN, host, or port involved.
- Whether the task is read-only diagnosis or a persistent config change.
- Any downtime constraints before applying netplan or route changes.

## Workflow

1. Inspect current interface, route, DNS, and reachability state first.
2. Choose the matching workflow below for connectivity, port reachability, VLAN, or time-sync work.
3. Apply the smallest safe change and validate immediately.
4. Confirm the network path behaves as expected after the change.

## Quality standards

- Prefer observation before mutation.
- Treat persistent network changes as high-risk and validate them carefully.
- Distinguish local host issues from remote service issues.

## Anti-patterns

- Applying netplan without verifying the exact target interface and route.
- Debugging with only `ping` when port-level or DNS-level evidence is needed.
- Mixing firewall and non-firewall networking changes in one step.

## Outputs

- The network diagnosis or change plan.
- The exact commands used to validate state.
- Post-change verification for reachability, resolution, or sync state.

## References

- [`references/netplan-reference.md`](references/netplan-reference.md)
- [`references/diagnostics-tree.md`](references/diagnostics-tree.md)

**This skill is self-contained.** Every command below is a standard
Ubuntu/Debian tool (`ip`, `ss`, `netplan`, `dig`, `ping`, `mtr`,
`resolvectl`, `chronyc`). The `sk-*` scripts in the **Optional fast path**
section are convenience wrappers — never required.

This skill owns everything about how a server talks to the network *below*
the firewall and *above* the application layer: interfaces, addresses,
routes, name resolution from the server's perspective, and time sync.

It does **not** own:

- **Firewall rules** — `linux-firewall-ssl`.
- **Authoritative DNS serving** (bind9/unbound) — `linux-dns-server`.
- **Mail / MX records** — `linux-mail-server`.
- **Deep packet capture for incident triage** — `linux-troubleshooting`.

Informed by *Linux Network Administrator's Guide* (translated from legacy
`ifconfig`/`route` to modern `ip`/`ss`) and the Canonical *Ubuntu Server
Guide* (netplan, systemd-networkd, systemd-resolved).

---

## When to use

- "The server can't reach the internet" / "can't resolve DNS" / "bad gateway."
- Adding a new network interface, bridge, bond, or VLAN.
- Changing an IP address or default route on a live server.
- Validating netplan YAML before applying it.
- Testing whether a port is reachable from the server.
- Verifying NTP sync is healthy.

## When NOT to use

- Opening or closing firewall ports — use `linux-firewall-ssl`.
- Debugging why a remote service can't reach this server when the firewall
  is the cause — use `linux-firewall-ssl`.
- Mail delivery problems — use `linux-mail-server`.

---

## Standing rules

1. **Netplan is the source of truth for configuration.** Never edit
   `/etc/network/interfaces` on a modern Ubuntu server. All changes go
   through `/etc/netplan/*.yaml`.
2. **Always `sudo netplan try` before `sudo netplan apply`.** `try` has a
   120s revert timeout — if connectivity breaks, it rolls back.
3. **DNS lives in `systemd-resolved`.** `/etc/resolv.conf` is a symlink —
   never edit it directly; set resolvers via netplan's `nameservers.addresses`.
4. **Test DNS from the server itself, not from your laptop.** A cached
   local resolver on your laptop will lie. Query both the server's own
   resolver and a public one to distinguish.
5. **Modern tools only.** `ip addr` not `ifconfig`. `ss -tulnp` not
   `netstat`. `ip route` not `route -n`. `resolvectl` not `nslookup` for
   systemd-resolved state.
6. **Confirm before applying route changes over SSH.** A broken default
   route = no way back in.

---

## Quick reference — manual commands

### Inspect current state

```bash
ip -c addr                                    # all interfaces + addresses
ip -c link                                    # link state, MAC, MTU
ip -c route                                   # routing table
ip route get 8.8.8.8                          # which iface will this go out?
ss -tulnp                                     # listening ports with owning process
ss -tan state established                     # active connections
nmcli device status                           # if NetworkManager is in use
resolvectl status                             # DNS resolvers per link
resolvectl query example.com                  # resolve via systemd-resolved
```

### Test connectivity

```bash
ping -c 3 8.8.8.8                             # L3 to the public internet
ping -c 3 $(ip route | awk '/default/{print $3; exit}')   # gateway
mtr -c 10 --report example.com                # path + loss + latency
traceroute example.com                        # hop-by-hop (apt install traceroute)

# TCP reachability without nmap:
(echo > /dev/tcp/example.com/443) 2>/dev/null && echo OK || echo FAIL

# UDP reachability (requires nc):
nc -u -z -v example.com 53
```

### Resolve DNS correctly

```bash
# Resolver 1: what systemd-resolved returns (what applications actually see)
resolvectl query example.com
resolvectl query -p dns -t A example.com

# Resolver 2: bypass the local resolver — query a public one directly
dig @1.1.1.1 example.com +short
dig @8.8.8.8 example.com +short

# Reverse DNS:
dig -x 8.8.8.8 +short

# If 1 and 2 disagree, your local resolver (systemd-resolved or /etc/hosts)
# is the problem, not upstream DNS.
```

### Edit netplan

```bash
sudo nano /etc/netplan/01-linux-skills.yaml
sudo chmod 600 /etc/netplan/*.yaml            # contains secrets for wifi

# Generate backend config without applying:
sudo netplan generate

# Try with 120s auto-revert — use this over SSH:
sudo netplan try

# Apply permanently (use only after `try` succeeds):
sudo netplan apply
```

Full netplan YAML syntax, 8 worked examples, renderers, policy routing,
bonds, bridges, VLANs — see [`references/netplan-reference.md`](references/netplan-reference.md).

### Check NTP sync

```bash
# chrony (Ubuntu Server default):
chronyc tracking                              # current offset, stratum, leap
chronyc sources -v                            # peers, reachability
chronyc makestep                              # force immediate step correction

# systemd-timesyncd (Ubuntu Desktop default):
timedatectl show-timesync --all
timedatectl status
```

---

## Typical workflows

### Workflow: "The server can't reach the internet"

Walk the diagnostics tree in [`references/diagnostics-tree.md`](references/diagnostics-tree.md).
Condensed version:

```bash
# 1. Link up?
ip -c link | grep -E "state (UP|DOWN)"

# 2. Address assigned?
ip -c addr show dev <iface>

# 3. Default route present?
ip route | grep default

# 4. Gateway reachable?
ping -c 3 $(ip route | awk '/default/{print $3; exit}')

# 5. External reachable by IP (skips DNS)?
ping -c 3 1.1.1.1

# 6. DNS resolving?
resolvectl query example.com
dig @1.1.1.1 example.com +short   # bypass local resolver to confirm

# 7. If 5 works but 6 doesn't → DNS problem. Check `resolvectl status`
#    and `cat /run/systemd/resolve/resolv.conf`.
# 8. If 4 works but 5 doesn't → gateway or upstream ISP problem.
# 9. If 3 is missing → fix default route via netplan.
```

### Workflow: "Can this server reach that port on that host?"

```bash
# Local listen check (is it OUR firewall or NOT OUR box?):
ss -tulnp | grep ':<port>'

# TCP handshake from this server:
(echo > /dev/tcp/db.internal/5432) 2>/dev/null && echo OK || echo FAIL

# Path investigation if it fails:
mtr -c 10 -T -P 5432 --report db.internal    # TCP mtr to the exact port
traceroute -T -p 5432 db.internal

# From the server, check the remote's open ports if you have access:
ssh admin@db.internal 'ss -tulnp | grep 5432'
```

### Workflow: "Adding a new VLAN on a trunk"

```bash
# 1. Edit netplan (see references/netplan-reference.md for VLAN stanza)
sudo nano /etc/netplan/01-linux-skills.yaml

# 2. Validate and dry-run
sudo netplan generate                         # parses YAML; errors here = bad file
sudo netplan try                               # apply with 120s revert

# 3. Verify the new interface:
ip -c link show dev vlan100
ip -c addr show dev vlan100

# 4. Confirm to persist (type Enter in the `try` session)
```

### Workflow: "NTP sync is drifting"

```bash
chronyc tracking                              # look at System time offset
chronyc sources -v                            # any peers reach 0?
chronyc makestep                              # immediate step (use once, then investigate)

# If all sources are unreachable, check:
ss -tunap | grep 123                          # NTP port 123/udp
ping -c 3 pool.ntp.org
sudo systemctl status chrony
journalctl -u chrony -n 50 --no-pager
```

---

## Troubleshooting / gotchas

- **`/etc/resolv.conf` is a symlink.** Never edit it. Changes vanish on
  next boot. Always configure via netplan `nameservers.addresses` or
  systemd-resolved drop-ins.
- **`netplan apply` can cut your SSH.** Use `netplan try` first. If you're
  desperate and have no console, run this to auto-revert:
  `sudo timeout 60 bash -c 'netplan apply; sleep 55; ip link set <iface> down'`.
  Ugly but survives a bad apply.
- **Two DNS servers both "work" but one is wrong.** systemd-resolved picks
  per-link DNS. If multiple interfaces have nameservers, it may split-query.
  `resolvectl status` shows exactly which resolver is consulted for which
  domain.
- **`ifconfig` still "works" on old servers.** It's provided by
  `net-tools` and frozen. Don't rely on anything it reports for bonded,
  VLAN, or aliased interfaces — it truncates silently.
- **Policy routing.** If packets from one interface are leaving via
  another, you need `routing-policy` rules (see the reference file). The
  symptom is "ping works, TCP doesn't" or asymmetric routing.
- **MTU mismatches on tunnels.** PMTU discovery is often broken by
  firewalls that drop ICMP. Symptom: SSH connects but a large file
  transfer hangs. Lower MTU to 1400 on the tunnel interface.

---

## References

- [`references/netplan-reference.md`](references/netplan-reference.md) —
  complete netplan YAML syntax and 8 worked examples.
- [`references/diagnostics-tree.md`](references/diagnostics-tree.md) —
  symptom-driven decision tree for networking problems.
- Book: *Linux Network Administrator's Guide* (Kirch & Dawson, 2nd ed.) —
  routing, resolver, subnetting fundamentals. Translate `ifconfig`/`route`
  to `ip`.
- Book: *Ubuntu Server Guide* (Canonical, Focal) — netplan, networkd,
  resolved chapters.
- Man pages: `netplan(5)`, `ip(8)`, `ss(8)`, `resolvectl(1)`, `chronyc(1)`.

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-network-admin` installs the
following convenience wrappers. They are never required — the manual
commands above are always the source of truth.

| Task | Fast-path script |
|---|---|
| One-screen report: interfaces, addresses, default gateway, DNS, ports | `sudo sk-net-status` |
| Validate netplan YAML, `try` with revert, apply on confirm | `sudo sk-netplan-apply` |
| Test TCP/UDP port reachability with traceroute on failure | `sudo sk-port-check --target <h> --port <n>` |
| Forward + reverse DNS lookup against local and public resolvers | `sudo sk-dns-check <domain>` |
| NTP sync state, offset, peers | `sudo sk-ntp-sync` |

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-network-admin
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-net-status | scripts/sk-net-status.sh | no | One-screen report: interfaces, addresses, default gateway, DNS servers, open ports, link state. |
| sk-netplan-apply | scripts/sk-netplan-apply.sh | no | Validate netplan YAML, run `netplan try` with timeout rollback, confirm, then `apply`. |
| sk-port-check | scripts/sk-port-check.sh | no | Test TCP/UDP port reachability from this server to a target, with traceroute on failure. |
| sk-dns-check | scripts/sk-dns-check.sh | no | Forward + reverse DNS lookup against local resolver, systemd-resolved, and a public resolver; flags mismatches. |
| sk-ntp-sync | scripts/sk-ntp-sync.sh | no | Report chrony/timesyncd state, offset, peers, last successful sync.
