# nftables & iptables reference (both families)

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

This is the **raw netfilter** layer that sits *underneath* UFW and firewalld.
You rarely touch it on a managed host — UFW
([`ufw-reference.md`](ufw-reference.md)) and firewalld
([`firewalld-reference.md`](firewalld-reference.md)) are the recommended
front-ends — but you reach for it when:

- a front-end can't express a rule (custom NAT, port forwarding, complex match);
- you inherited a host configured directly with `iptables`/`nft`;
- you are debugging *why* a front-end's rule isn't taking effect (read the
  backend ruleset);
- you are doing low-level container/router/bridge work.

> **The backend relationship.** On modern Debian/Ubuntu *and* the whole RHEL
> family, both UFW and firewalld emit **nftables** rules through the kernel's
> `nf_tables` subsystem. `iptables` on these systems is usually the
> `iptables-nft` shim (`iptables` command → nftables backend). So
> `nft list ruleset` shows you firewalld's *and* UFW's rules plus anything you
> added by hand. **Do not mix hand-written `nft`/`iptables` rules with an
> active front-end on the same chains** — the front-end owns its tables/chains
> and will overwrite them on reload. Either let the front-end manage the host,
> or stop it (`systemctl disable --now firewalld` / `ufw disable`) and manage
> netfilter directly.

---

## Distro support

| Concern | Debian/Ubuntu | RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) |
|---|---|---|
| Default front-end | `ufw` | `firewalld` |
| Backend | nftables (`nf_tables`); `iptables` is the `iptables-nft` shim | nftables (`nf_tables`); `iptables` is the `iptables-nft` shim |
| `nft` package | `apt install nftables` | preinstalled (`nftables`) |
| iptables compat package | `iptables` (legacy `iptables-legacy` via alternatives) | `iptables-nft` (legacy retired in RHEL 9+) |
| Persist nftables | `nftables.service` reads `/etc/nftables.conf` | `nftables.service` reads `/etc/sysconfig/nftables.conf` |
| Persist iptables | `netfilter-persistent` / `iptables-persistent` → `/etc/iptables/rules.v4` `rules.v6` | `iptables-save` → file, restored by hand/unit (legacy) |
| Migration tool | `iptables-restore-translate` | `iptables-restore-translate` |

Both families share the same kernel framework, the same `nft` syntax, and the
same `iptables-nft` command surface. Only **package names and the persistence
file paths differ** — captured in the rows above.

---

## iptables (legacy command surface, nft backend)

iptables is linear: each packet walks the rules of a chain top-to-bottom until
one matches. Built-in chains live in the `filter` table: `INPUT`, `FORWARD`,
`OUTPUT`. (Grounded on Mastering Debian Linux, "Setting up Firewalls with UFW
and IPTables".)

```bash
# View
sudo iptables -L -n -v                 # numeric, with counters
sudo iptables -S                       # rules as the commands that created them
sudo iptables -L INPUT --line-numbers  # numbered, for deletion

# Default policies (deny inbound + forward, allow outbound)
sudo iptables -P INPUT DROP
sudo iptables -P FORWARD DROP
sudo iptables -P OUTPUT ACCEPT

# Add rules (order matters — loopback + established first)
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT      # SSH
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT      # HTTP
sudo iptables -A INPUT -j LOG --log-prefix "iptables-drop: " --log-level 7

# Insert at a position instead of appending
sudo iptables -I INPUT 1 -s 203.0.113.5 -j ACCEPT

# Delete: by spec, or by line number
sudo iptables -D INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -L INPUT --line-numbers
sudo iptables -D INPUT 3

# Flush everything in a chain / table
sudo iptables -F INPUT
```

A complete starter `filter`-table policy (SSH + HTTP, default-deny) is exactly
the Mastering-Debian sample script, reproduced in `sk-nft-apply --profile
web-server`.

### NAT, masquerade, port forwarding (iptables)

```bash
# Enable IP forwarding first (kernel) — persist in /etc/sysctl.d/
sudo sysctl -w net.ipv4.ip_forward=1

# Masquerade an internal LAN out via eth0 (SNAT to the interface address)
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Forward public :80 to an internal host:port (DNAT)
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 192.0.2.10:8080
sudo iptables -A FORWARD -p tcp -d 192.0.2.10 --dport 8080 -j ACCEPT
```

### Persistence (iptables)

| Family | How |
|---|---|
| Debian/Ubuntu | `sudo apt install iptables-persistent`; rules in `/etc/iptables/rules.v4` and `rules.v6`. Save: `sudo netfilter-persistent save` (or `sudo iptables-save > /etc/iptables/rules.v4`). Reload at boot: `netfilter-persistent` unit. |
| RHEL family | No `iptables-services` by default on RHEL 9+ (iptables-legacy retired). Use nftables (below). For a one-off: `sudo iptables-save > /etc/sysconfig/iptables` and restore manually. |

```bash
# Debian — save current live rules to the persistence files
sudo netfilter-persistent save
sudo systemctl enable netfilter-persistent

# Manual, either family
sudo iptables-save  > /etc/iptables/rules.v4
sudo ip6tables-save > /etc/iptables/rules.v6
sudo iptables-restore < /etc/iptables/rules.v4   # reload
```

---

## nftables (the modern replacement)

nftables replaces iptables/ip6tables/arptables/ebtables with one tool (`nft`),
one syntax, IPv4+IPv6 in a single `inet` family, **atomic** ruleset reloads,
and built-in sets/maps. (Grounded on RHEL 9 for SysAdmins, Recipe #83.)

> `[GROUNDING-GAP: modern nft expression syntax (sets, maps, named counters, flowtables) — the books cover only the NAT/migrate basics; deepen with https://wiki.nftables.org]`

### Mental model

- **Table** — a namespace for a protocol family: `ip`, `ip6`, `inet`
  (v4+v6), `arp`, `bridge`, `netdev`.
- **Chain** — a list of rules inside a table. A *base* chain attaches to a
  netfilter **hook** (`input`, `forward`, `output`, `prerouting`,
  `postrouting`) with a `type` (`filter`/`nat`/`route`), a `priority`, and a
  default `policy`.
- **Rule** — match expressions + a verdict (`accept`, `drop`, `reject`,
  `jump`, `goto`, `return`).

### View

```bash
sudo nft list ruleset                  # the whole machine — incl. firewalld/ufw output
sudo nft list tables
sudo nft list table inet filter
sudo nft -a list chain inet filter input   # -a shows rule handles (needed to delete)
```

### Build a filter ruleset from scratch

```bash
sudo nft add table inet filter
sudo nft add chain inet filter input '{ type filter hook input priority 0 ; policy drop ; }'
sudo nft add chain inet filter forward '{ type filter hook forward priority 0 ; policy drop ; }'

sudo nft add rule inet filter input iif lo accept
sudo nft add rule inet filter input ct state established,related accept
sudo nft add rule inet filter input tcp dport 22 accept
sudo nft add rule inet filter input tcp dport { 80, 443 } accept   # a set literal
sudo nft add rule inet filter input counter drop
```

### Delete

```bash
sudo nft -a list chain inet filter input        # find the handle
sudo nft delete rule inet filter input handle 7 # delete one rule
sudo nft flush chain inet filter input          # empty a chain
sudo nft delete table inet filter               # remove a whole table
```

### Default policy

The policy is a property of the **base chain** (`policy drop` / `policy
accept`), set at creation or changed in place:

```bash
sudo nft add chain inet filter input '{ policy drop ; }'   # re-declares policy
```

### NAT / masquerade / port forwarding (nftables)

```bash
# Masquerade an internal LAN out via ens3
sudo nft add table ip nat
sudo nft add chain ip nat postrouting '{ type nat hook postrouting priority 100 ; }'
sudo nft add rule ip nat postrouting oifname "ens3" masquerade

# Forward public :80 to an internal host:port (DNAT)
sudo nft add chain ip nat prerouting '{ type nat hook prerouting priority -100 ; }'
sudo nft add rule ip nat prerouting tcp dport 80 dnat to 192.0.2.1:8080
```

(NAT examples grounded on RHEL 9 for SysAdmins, Recipe #83 "Configuring NAT
with nftables".)

### Scripts, sets and maps

A native ruleset file is an executable script. Always `flush ruleset` at the
top so the load is atomic and idempotent:

```nft
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
    set trusted_v4 { type ipv4_addr ; elements = { 10.0.0.0/8, 192.0.2.5 } }

    chain input {
        type filter hook input priority 0 ; policy drop ;
        iif lo accept
        ct state established,related accept
        ip saddr @trusted_v4 accept
        tcp dport { 22, 80, 443 } accept
        counter comment "default-drop"
    }
}
```

```bash
sudo nft -f /etc/nftables.conf        # load atomically; replaces the live ruleset
sudo nft -c -f /etc/nftables.conf     # -c = check syntax only, do NOT apply (dry run)
```

(Script format, sets, and verdict maps grounded on RHEL 9 for SysAdmins,
Recipe #83 "Writing and executing nftables scripts" / "Advanced features".)

### Persistence (nftables)

| Family | File loaded by `nftables.service` |
|---|---|
| Debian/Ubuntu | `/etc/nftables.conf` |
| RHEL family | `/etc/sysconfig/nftables.conf` (which `include`s your `.nft` files) |

```bash
# Dump live ruleset into the persistence file, then enable the unit
sudo sh -c 'nft list ruleset > /etc/nftables.conf'          # Debian
sudo sh -c 'nft list ruleset > /etc/sysconfig/nftables.conf' # RHEL
sudo systemctl enable --now nftables
```

`nftables.service` runs `nft -f <file>` at boot. Verify with
`systemctl status nftables` and `nft list ruleset`.

---

## IP routing-table manipulation (`ip route`)

Firewalls and NAT only matter once packets are routed. The routing table is
managed with `ip route` (the `iproute2` package, present on both families;
`route`/`netstat -r` are deprecated). Changes made with `ip` are **runtime
only** — persist them via the distro's network config.

```bash
ip route show                       # the main routing table
ip -6 route show
ip route get 8.8.8.8                # which route/source a packet would use

sudo ip route add 10.20.0.0/16 via 192.0.2.1 dev eth0   # static route
sudo ip route del 10.20.0.0/16
sudo ip route add default via 192.0.2.254               # default gateway
sudo ip route replace default via 192.0.2.254 dev eth0  # add-or-update

ip rule show                        # policy-routing rules (multi-table)
ip route show table all
```

| Persist a static route | Debian/Ubuntu | RHEL family |
|---|---|---|
| Method | netplan (`routes:` under the interface) or `/etc/network/interfaces` (`up ip route add …`) | NetworkManager: `nmcli connection modify <con> +ipv4.routes "10.20.0.0/16 192.0.2.1"` then `nmcli connection up <con>` |

> `[GROUNDING-GAP: ip route / iproute2 routing-table management — neither book covers static-route persistence in depth; deepen with iproute2 man pages (ip-route(8)) and netplan / NetworkManager docs]`

---

## Migrating iptables → nftables

When you inherit an iptables host and want native nftables:

```bash
# 1. Dump existing iptables rules
sudo iptables-save  > /root/iptables.dump
sudo ip6tables-save > /root/ip6tables.dump

# 2. Translate to nft syntax
sudo iptables-restore-translate  -f /root/iptables.dump  > /etc/nftables/ruleset-from-iptables.nft
sudo ip6tables-restore-translate -f /root/ip6tables.dump > /etc/nftables/ruleset-from-ip6tables.nft

# 3. include the translated files from your main nftables config, then
sudo systemctl disable --now iptables 2>/dev/null || true
sudo systemctl enable  --now nftables
sudo nft list ruleset            # verify
```

(Migration steps grounded on RHEL 9 for SysAdmins, Recipe #83 "Migrating from
iptables to nftables".)

---

## Safety checklist

- **Never** lock yourself out: before a default-`drop` policy on a remote host,
  always have an `accept` rule for SSH (`tcp dport 22 accept`) **and** for
  `ct state established,related` *above* the drop. Test with a second session.
- Prefer `nft -c -f file` (check) or the front-end's permanent/runtime split
  before committing.
- On a host where firewalld/UFW is active, change rules **through the
  front-end**; raw `nft` edits to its chains are lost on reload.
- Persist deliberately — live `nft`/`iptables`/`ip route` changes vanish on
  reboot until written to the persistence file / network config above.

---

## References

- [`ufw-reference.md`](ufw-reference.md) — the Debian/Ubuntu front-end.
- [`firewalld-reference.md`](firewalld-reference.md) — the RHEL-family front-end.
- Man pages: `nft(8)`, `iptables(8)`, `iptables-nft(8)`,
  `iptables-restore-translate(8)`, `ip-route(8)`, `nftables.service`.
- Upstream: <https://wiki.nftables.org> (modern syntax, sets/maps/flowtables).
- Books: RHEL 9 for SysAdmins (Recipe #83); Mastering Debian Linux
  ("Setting up Firewalls with UFW and IPTables").
