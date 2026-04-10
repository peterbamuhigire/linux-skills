---
name: linux-network-admin
description: Manage Ubuntu/Debian server networking — interfaces, routes, netplan, DNS resolution, NTP, reachability. Use for any non-firewall, non-mail networking task on a managed server. Handles `ip`, `ss`, `nmcli`, `netplan try/apply`, and diagnostic tooling.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---

# Linux Network Administration

This skill owns everything about how a server talks to the network *below*
the firewall and *above* the application layer: interfaces, addresses,
routes, name resolution from the server's perspective, and time
synchronization.

It does **not** own:

- **Firewall rules** — that's `linux-firewall-ssl`.
- **Authoritative DNS serving** (bind9/unbound) — that's `linux-dns-server`.
- **Mail server MX/SPF/DKIM** — that's `linux-mail-server`.
- **Deep packet analysis for troubleshooting** — that belongs in
  `linux-troubleshooting`.

Informed by *Linux Network Administrator's Guide* (translated from legacy
`ifconfig`/`route` to modern `ip`/`ss`) and the Canonical *Ubuntu Server
Guide* (netplan, systemd-networkd, systemd-resolved).

---

## When to use

- "The server can't reach the internet" / "can't resolve DNS" / "bad gateway."
- Adding a new network interface, bridge, bond, or VLAN.
- Changing an IP address or default route.
- Validating netplan YAML before applying it.
- Testing whether a port is reachable from the server.
- Verifying NTP sync is healthy.

## When NOT to use

- Opening or closing ports for clients — use `linux-firewall-ssl`.
- Debugging why a *remote* service can't reach this server when the firewall
  is clearly the cause — use `linux-firewall-ssl`.
- Mail delivery problems — use `linux-mail-server`.

---

## Standing rules

1. **Netplan is the source of truth for configuration.** Never edit
   `/etc/network/interfaces` on an Ubuntu server. All changes go through
   `/etc/netplan/*.yaml`.
2. **Always `netplan try` before `netplan apply`.** `try` has a 120s revert
   timeout — if you lose connectivity, it rolls back. `sk-netplan-apply`
   enforces this.
3. **DNS lives in `systemd-resolved` on modern Ubuntu.** `/etc/resolv.conf`
   is a symlink. Never edit it directly; set resolvers via netplan's
   `nameservers.addresses`.
4. **Test from the server itself, not from your laptop.** A cached local
   resolver on your laptop will lie. Use `sk-dns-check` which queries both
   local systemd-resolved and a public resolver.
5. **Modern tools only.** `ip addr` not `ifconfig`. `ss -tulnp` not
   `netstat`. `ip route` not `route -n`. Legacy tools are not guaranteed
   installed.
6. **Confirm before applying route changes over SSH.** A broken default
   route = no way back in. `sk-netplan-apply` requires confirmation *and* a
   session test.

---

## Typical workflows

### "The server can't reach the internet"

1. `sk-net-status` — see interfaces, default gateway, DNS servers, listening
   ports in one report.
2. Check the outcome against the report format in
   `references/diagnostic-tree.md`.
3. If DNS is the culprit, `sk-dns-check <domain>` — tests forward + reverse
   against local resolver and public resolver.
4. If routing is the culprit, `ip route show`, `ip route get 8.8.8.8`, then
   fix in `/etc/netplan/*.yaml` and apply with `sk-netplan-apply`.

### "Can this server reach that port on that host?"

```bash
sk-port-check --target db.internal --port 5432 --protocol tcp
```

Runs the local `ss` check, TCP handshake attempt, optional traceroute, and
reports each hop's status.

### "Is NTP sync healthy?"

```bash
sk-ntp-sync
```

Reports chrony/systemd-timesyncd state, offset from upstream, peer list, last
successful sync.

### "Adding a new VLAN interface"

1. Edit `/etc/netplan/01-linux-skills.yaml` to add the VLAN stanza.
2. `sk-netplan-apply` — validates, runs `netplan try`, confirms, applies.
3. `sk-net-status` — verify the new interface is up and addressed.

---

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
| sk-ntp-sync | scripts/sk-ntp-sync.sh | no | Report chrony/timesyncd state, offset, peers, last successful sync. |

---

## See also

- `linux-firewall-ssl` — UFW, certbot, TLS config.
- `linux-dns-server` — authoritative DNS (bind9/unbound).
- `linux-mail-server` — MX/SPF/DKIM/DMARC.
- `linux-troubleshooting` — decision trees including `sk-why-cant-connect`.
