# Netplan Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

The complete copy-pasteable netplan YAML reference for Ubuntu 22.04+ servers.
Read this whenever editing `/etc/netplan/*.yaml` — for adding an interface,
changing an IP, building a bridge, trunking VLANs, bonding NICs, or setting
DNS. Every example is cross-checked against the Canonical *Ubuntu Server
Guide* and the current netplan(5). On a modern Ubuntu server, netplan is the
single source of truth — never edit `/etc/network/interfaces` or run
`ifconfig` to "save" a change.

## Table of contents

- [File layout](#file-layout)
- [Top-level structure](#top-level-structure)
- [Renderers: networkd vs NetworkManager](#renderers-networkd-vs-networkmanager)
- [Addressing: DHCP, static, dual-stack](#addressing-dhcp-static-dual-stack)
- [Nameservers and search domains](#nameservers-and-search-domains)
- [Routes and gateways](#routes-and-gateways)
- [Policy routing](#policy-routing)
- [Matching and renaming interfaces](#matching-and-renaming-interfaces)
- [Bridges, bonds, VLANs, wifis](#bridges-bonds-vlans-wifis)
- [Worked examples](#worked-examples)
- [Applying: try, apply, generate, get](#applying-try-apply-generate-get)
- [Common errors](#common-errors)
- [Sources](#sources)

## File layout

Netplan reads every `*.yaml` file in these directories in order:

1. `/run/netplan/` — volatile, written by cloud-init.
2. `/etc/netplan/` — your edits live here.
3. `/lib/netplan/` — distro defaults.

Within a directory, files load in lexicographic order; later keys override
earlier ones. Cloud-init writes `50-cloud-init.yaml` so your own file
(`01-linux-skills.yaml` or `99-override.yaml`) can override it. Lock
permissions — newer netplan warns when YAML is world-readable because wifi
passwords may live there:

```bash
sudo chmod 600 /etc/netplan/*.yaml
```

## Top-level structure

```yaml
network:
  version: 2
  renderer: networkd
  ethernets: {}
  bonds: {}
  bridges: {}
  vlans: {}
  wifis: {}
```

`version: 2` is required. The five device-type maps are all optional —
include only the ones you use. `renderer:` can be overridden per
device-type block.

## Renderers: networkd vs NetworkManager

| Renderer | Use on | State command |
|---|---|---|
| `networkd` | Every server, VM, container host. | `networkctl`, `networkctl status <dev>` |
| `NetworkManager` | Desktops, laptops, roaming wifi. | `nmcli device status` |

Do not mix. Switching renderers bounces every link. Check current renderer:

```bash
sudo netplan get renderer
systemctl is-active systemd-networkd
```

## Addressing: DHCP, static, dual-stack — key reference

Per-device keys: `dhcp4: true|false`, `dhcp6: true|false`, `addresses:` (a
list of `ip/prefix` entries). For dual-stack list both families in
`addresses:` and both default routes under `routes:` — quote IPv6 literals
or YAML parses `::` as an empty mapping. See Worked Example 1 (static v4),
Example 2 (dual-stack).

The older `gateway4: 10.10.10.1` key is **deprecated** and prints a warning
on apply — always use `routes: - to: default, via: <ip>` now.

DHCP-with-overrides pattern:

```yaml
    enp3s0:
      dhcp4: true
      dhcp4-overrides:
        use-dns: false       # ignore DNS advertised by DHCP
        use-ntp: false       # ignore NTP advertised by DHCP
        route-metric: 200    # push the default route to a lower priority
```

Use this on a management NIC that must not hijack DNS or be the preferred
default route.

## Nameservers and search domains

`nameservers:` lives *inside* a device block. Two keys only — `addresses:`
(v4 and/or v6 IPs) and `search:` (DNS suffix list for short-name lookups).

```yaml
      nameservers:
        search: [example.com, sales.example.com]
        addresses: [1.1.1.1, 8.8.8.8]
```

A `ping server1` will try `server1.example.com`, then
`server1.sales.example.com`. Netplan does not write `/etc/resolv.conf`
directly — it configures systemd-resolved. The file is a symlink to
`/run/systemd/resolve/stub-resolv.conf`; never edit it by hand. Verify with:

```bash
resolvectl status
```

## Routes and gateways

The `routes:` list replaces the deprecated `gateway4:` / `gateway6:` keys.

```yaml
      routes:
        - to: default            # or "0.0.0.0/0" / "::/0" / "10.20.0.0/16"
          via: 10.10.10.1        # next hop
          metric: 100            # optional, lower = preferred
          on-link: false         # true only if gateway is off-subnet
          table: 200             # optional, for policy routing
```

Multiple static routes are fine:

```yaml
      routes:
        - to: default
          via: 10.10.10.1
        - to: 10.20.0.0/16
          via: 10.10.10.254
          metric: 50
        - to: 192.168.88.0/24
          via: 10.10.10.253
```

Verify:

```bash
ip route show
ip -6 route show
ip route get 8.8.8.8
```

## Policy routing

Use `routing-policy:` combined with `table:` on routes to pick a routing
table per source address. This fixes the classic multi-homed
"reply-leaves-the-wrong-NIC" asymmetric routing problem. Each
`routing-policy:` entry takes `from:`, `to:`, `table:`, `priority:`,
`mark:`, or `type-of-service:`. Pair it with `table: <n>` on the matching
route. See Worked Example 6 for the full dual-uplink config.

Verify after apply:

```bash
ip rule show
ip route show table 101
ip route show table 102
```

## Matching and renaming interfaces

Use `match:` when kernel names flip between boots or you want stable
logical names on a multi-NIC box:

```yaml
    eth_lan0:
      match:
        macaddress: 00:11:22:33:44:55
      set-name: eth_lan0
      dhcp4: true
```

**What this does:** finds the NIC with that MAC, renames it to `eth_lan0`,
runs DHCP. `match:` keys: `macaddress:`, `name:` (glob, e.g. `"enp*"`),
`driver:` (e.g. `"mlx4_en"`).

Other per-device keys that apply to most types: `mtu:` (jumbo frames),
`macaddress:` (override), `wakeonlan: true`, `optional: true` (don't block
boot if no carrier), `link-local: []` (disable link-local).

## Bridges, bonds, VLANs, wifis — key reference

**Bridge** (`bridges:` map) keys: `interfaces:` list of members, `addresses:`,
`routes:`, and a `parameters:` block with `stp`, `forward-delay`,
`hello-time`, `max-age`, `priority`, `ageing-time`, `path-cost`,
`port-priority`. See Worked Example 3.

**Bond** (`bonds:` map) keys: `interfaces:` list of slaves, `addresses:`,
`routes:`, and a `parameters:` block with `mode:` (`balance-rr`,
`active-backup`, `balance-xor`, `broadcast`, `802.3ad`, `balance-tlb`,
`balance-alb`), `lacp-rate:`, `mii-monitor-interval:`,
`transmit-hash-policy:`. Use `active-backup` for switch-agnostic failover,
`802.3ad` with matching switch config for LACP. See Worked Example 5.

**VLAN** (`vlans:` map) keys: `id:` (1-4094), `link:` (parent device name),
plus the usual `addresses:` / `routes:` / `nameservers:`. Name convention:
`<parent>.<id>`. Parent must exist in `ethernets:` or `bonds:` with no IP.
See Worked Example 4.

**Wifi** (`wifis:` map, NetworkManager renderer) keys: `access-points:`
mapping of SSID to either a flat `password:` (WPA2-PSK) or an `auth:` block
(`key-management: eap`, `method:`, `identity:`, `password:`) for
enterprise. See Worked Example 7. `chmod 600` mandatory because of stored
passwords.

## Worked examples

### Example 1 — Single static IPv4 (classic small server)

```yaml
# /etc/netplan/01-linux-skills.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp1s0:
      addresses: [192.168.1.50/24]
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
        search: [lan]
```

**What this does:** the 90%-of-the-time config — one NIC, one IP, one
gateway, two resolvers.

### Example 2 — Dual-stack public server

```yaml
# /etc/netplan/01-linux-skills.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      addresses:
        - 203.0.113.50/24
        - "2001:db8:10::50/64"
      routes:
        - to: default
          via: 203.0.113.1
        - to: "::/0"
          via: "2001:db8:10::1"
      nameservers:
        addresses:
          - 1.1.1.1
          - "2606:4700:4700::1111"
```

**What this does:** IPv4 + IPv6 public server; both default routes
installed; v4+v6 resolvers.

### Example 3 — LXD/KVM bridge for guests

```yaml
# /etc/netplan/01-linux-skills.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp3s0:
      dhcp4: false
      dhcp6: false
  bridges:
    br0:
      interfaces: [enp3s0]
      addresses: [192.168.1.10/24]
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
      parameters:
        stp: false
        forward-delay: 0
```

**What this does:** strips the physical NIC of its IP, puts the host on
`br0`, and lets LXD/KVM guests attach to `br0` to live on the LAN directly.

### Example 4 — VLAN trunk with management VLAN

```yaml
# /etc/netplan/01-linux-skills.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eno1:
      dhcp4: false
  vlans:
    mgmt.10:
      id: 10
      link: eno1
      addresses: [10.10.10.5/24]
      routes:
        - to: default
          via: 10.10.10.1
      nameservers:
        addresses: [10.10.10.1, 1.1.1.1]
    data.20:
      id: 20
      link: eno1
      addresses: [10.10.20.5/24]
    storage.30:
      id: 30
      link: eno1
      addresses: [10.10.30.5/24]
      mtu: 9000
```

**What this does:** three VLANs on one NIC — management (default route),
data (isolated), storage (jumbo frames, isolated). Switch port must be an
802.1Q trunk with all three VLAN IDs tagged.

### Example 5 — LACP bond for a database host

```yaml
# /etc/netplan/01-linux-skills.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp3s0f0: {dhcp4: false}
    enp3s0f1: {dhcp4: false}
  bonds:
    bond0:
      interfaces: [enp3s0f0, enp3s0f1]
      addresses: [10.50.0.10/24]
      routes:
        - to: default
          via: 10.50.0.1
      nameservers:
        addresses: [10.50.0.1, 1.1.1.1]
      parameters:
        mode: 802.3ad
        lacp-rate: fast
        mii-monitor-interval: 100
        transmit-hash-policy: layer3+4
```

**What this does:** bonds both ports of a dual-port NIC into an LACP LAG;
the bond itself carries the IP. Requires matching LACP config on the
switch.

### Example 6 — Multi-homed server with policy routing

```yaml
# /etc/netplan/01-linux-skills.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      addresses: [203.0.113.10/24]
      routes:
        - to: default
          via: 203.0.113.1
          table: 101
      routing-policy:
        - from: 203.0.113.10
          table: 101
    eth1:
      addresses: [198.51.100.10/24]
      routes:
        - to: default
          via: 198.51.100.1
          table: 102
      routing-policy:
        - from: 198.51.100.10
          table: 102
```

**What this does:** a server with two public uplinks on different ISPs.
Replies always leave by the interface that received the request, fixing the
asymmetric routing / reverse-path-filter drop.

### Example 7 — Wifi client

```yaml
# /etc/netplan/01-linux-skills.yaml
network:
  version: 2
  renderer: NetworkManager
  wifis:
    wlp2s0:
      dhcp4: true
      access-points:
        "OfficeWifi":
          password: "correct-horse-battery-staple"
```

**What this does:** joins one WPA2-PSK SSID with DHCP. Must use the
`NetworkManager` renderer for wifi roaming.

### Example 8 — Management VLAN on a bond (production)

```yaml
# /etc/netplan/01-linux-skills.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp1s0f0: {dhcp4: false}
    enp1s0f1: {dhcp4: false}
  bonds:
    bond0:
      interfaces: [enp1s0f0, enp1s0f1]
      parameters:
        mode: 802.3ad
        lacp-rate: fast
        mii-monitor-interval: 100
  vlans:
    bond0.10:
      id: 10
      link: bond0
      addresses: [10.0.10.50/24]
      routes:
        - to: default
          via: 10.0.10.1
      nameservers:
        addresses: [10.0.10.1, 1.1.1.1]
    bond0.20:
      id: 20
      link: bond0
      addresses: [10.0.20.50/24]
```

**What this does:** bonds two NICs for redundancy, then trunks two VLANs
over the bond. Management traffic (VLAN 10) carries the default route;
application traffic (VLAN 20) is isolated.

## Applying: try, apply, generate, get

```bash
sudo netplan try                  # apply with 120s rollback — ALWAYS over SSH
sudo netplan try --timeout 180    # longer countdown
sudo netplan apply                # commit, no safety net (console-only)
sudo netplan generate             # render to /run/systemd/network/, don't start
sudo netplan get                  # dump merged config
sudo netplan get ethernets.eth0   # drill into a key
sudo netplan set ethernets.eth0.dhcp4=true   # one-shot edit to 70-netplan-set.yaml
```

Rules:

- **Always `netplan try` when editing over SSH.** If the new routes kill
  your session, the rollback saves you a console trip.
- Use `netplan generate` to diff "what would change" without pulling the
  trigger.
- Prefer hand-edited files over `netplan set` for persistent config —
  easier to review and diff.

## Common errors

| Symptom | Cause | Fix |
|---|---|---|
| `unknown key 'gateway4'` | Deprecated. | Replace with `routes: [{to: default, via: <ip>}]`. |
| YAML parse error on a line with `::` | Unquoted IPv6. | Wrap in double quotes: `"2001:db8::1"`. |
| `netplan apply` does nothing | File not under `/etc/netplan/` or wrong extension. | Must be `*.yaml` under `/etc/netplan/`. |
| Static IP works, DNS doesn't | `nameservers:` at wrong indent — must be inside the device block. | Re-indent. |
| No default route after apply | `routes:` missing or `via:` not on any configured subnet. | Confirm the gateway is on a configured /24, or add `on-link: true`. |
| Boot hangs 2 min waiting for network | Secondary NIC with no cable blocking `systemd-networkd-wait-online`. | Add `optional: true`. |
| Two default routes, traffic takes wrong one | Equal metrics. | Bump one `metric:` or remove its default route. |
| DHCP resolvers override yours | DHCP client uses advertised DNS. | `dhcp4-overrides: {use-dns: false}`. |
| `netplan try` reverts after 120s even though it worked | Forgot to press Enter on the original SSH session. | Press Enter in time or use `--timeout`. |
| Warning about world-readable YAML | Permissions too open (wifi passwords risk). | `sudo chmod 600 /etc/netplan/*.yaml`. |

## Sources

- *Ubuntu Server Guide* (Canonical, Focal 20.04 LTS) — "Network
  Configuration" chapter: ethernet interfaces, logical names, temporary IP,
  DHCP client, static IP, name resolution, bridging, networkd-dispatcher.
- *Ubuntu Server Guide* — "iSCSI Network Configuration": `match:` +
  `set-name:` + `dhcp4-overrides: {route-metric:}` pattern.
- *Linux Network Administrator's Guide, 2nd Edition* (O'Reilly) — Chapter 5
  "Configuring TCP/IP Networking" (legacy `ifconfig`/`route`, translated to
  `ip`/`netplan` throughout).
- *Mastering Ubuntu* (Ghada Atef, 2023) — section V.II "Configuring
  networking and security settings" (context on NetworkManager vs
  command-line tools).
