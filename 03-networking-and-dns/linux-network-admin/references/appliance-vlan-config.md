# Appliance-Side VLAN Configuration (UniFi / pfSense / OPNsense / MikroTik)

## Scope

This reference covers configuring VLANs on **network appliances** — a UniFi
controller, pfSense/OPNsense firewall, or MikroTik RouterOS device. It is the
appliance-config counterpart to this skill's own host-side VLAN coverage.

**Do not duplicate netplan content here.** For tagging a VLAN on a Linux
**server's own NIC** (802.1Q trunk parsing, `vlans:` stanza syntax, bonded
trunk examples), see
[`netplan-reference.md`](netplan-reference.md#bridges-bonds-vlans-wifis) —
that file already has 8 worked netplan examples including VLAN trunks and a
management-VLAN-on-a-bond production example. This file starts where that one
stops: the switch/router/AP/firewall side of the same VLAN design, which a
Linux host's netplan config alone cannot configure.

Source: adapted from ECC's `skills/homelab-vlan-segmentation/SKILL.md`
(imported 2026-09-20; extracted appliance-config sections only — the host-side
VLAN material in that source skill duplicates what `netplan-reference.md`
already covers and was not imported).

## Distro support

Not applicable to this file specifically — it configures third-party
appliance firmware (UniFi controller software, pfSense/OPNsense FreeBSD-based
firewall OS, MikroTik RouterOS), none of which is a Linux distribution this
engine's Debian/Ubuntu-vs-RHEL-family matrix applies to. The parent skill,
[`linux-network-admin`](../SKILL.md), keeps its own `## Distro support`
section for the Linux-host side of this same VLAN design.

## VLAN Design Template (shared reference points)

```
VLAN  Name        Subnet              Gateway         Purpose
10    trusted     192.168.10.0/24     192.168.10.1    PCs, phones, laptops
20    iot         192.168.20.0/24     192.168.20.1    Smart home / IoT devices
30    servers     192.168.30.0/24     192.168.30.1    NAS, Linux hosts, self-hosted services
40    guest       192.168.40.0/24     192.168.40.1    Visitor Wi-Fi
99    management  192.168.99.0/24     192.168.99.1    Switch/AP/firewall web UIs
```

Creating VLANs on the appliance without also adding firewall rules provides
**no isolation** — inter-VLAN routing is open by default on every platform
below. Add explicit block rules immediately after creating each VLAN.

## UniFi Configuration

### Create Networks in UniFi Controller

```
Settings → Networks → Create New Network

For each VLAN:
  Name: IoT
  Purpose: Corporate  (gives DHCP + routing)
  VLAN ID: 20
  Network: 192.168.20.0/24
  Gateway IP: 192.168.20.1
  DHCP: Enable
  DHCP Range: 192.168.20.100 – 192.168.20.254
```

### Map SSIDs to VLANs (UniFi)

```
Settings → WiFi → Create New WiFi

  Name: IoT-Network
  Password: <separate password>
  Network: IoT  ← select your VLAN here
  # All devices connecting to this SSID land in VLAN 20

  Name: Guest
  Password: <guest password>
  Network: Guest
  Guest Policy: Enable  ← isolates guests from each other too
```

### UniFi Firewall Rules (Traffic Rules)

```
Settings → Traffic & Security → Traffic Rules

# Block IoT from reaching Trusted VLAN
  Action: Block
  Category: Local Network
  Source: IoT (192.168.20.0/24)
  Destination: Trusted (192.168.10.0/24)

# Allow IoT to reach internet only
  Action: Allow
  Source: IoT
  Destination: Internet

# Block Guest from all local networks
  Action: Block
  Source: Guest
  Destination: Local Networks
```

## pfSense / OPNsense Configuration

### Create VLANs

```
Interfaces → Assignments → VLANs → Add

  Parent Interface: em1  (your LAN NIC)
  VLAN Tag: 20
  Description: IoT

# Repeat for each VLAN, then assign each VLAN to an interface:
Interfaces → Assignments → Add
  Select the VLAN you created → click Add
  Enable the interface, set IP to gateway address (192.168.20.1/24)
```

### DHCP for Each VLAN

```
Services → DHCP Server → Select your VLAN interface

  Enable DHCP
  Range: 192.168.20.100 to 192.168.20.254
  DNS Servers: <your DNS server IP, e.g. a self-hosted resolver or sinkhole>
```

If that DNS server is Pi-hole, see
[`../../linux-dns-server/references/pihole-blocklist-sinkholing.md`](../../linux-dns-server/references/pihole-blocklist-sinkholing.md)
for install and blocklist management; for a general authoritative/recursive
resolver on a Linux host, see the parent `linux-dns-server` skill directly.

### Firewall Rules (pfSense/OPNsense)

```
# Rules are processed top-to-bottom, first match wins.

# On the IoT interface (VLAN 20):
  Rule 1: Allow IoT → DNS sinkhole/resolver  ← MUST come before the RFC1918 block rule
    Protocol: UDP/TCP
    Source: IoT net
    Destination: <DNS server IP> port 53
    Action: Allow

  Rule 2: Block IoT → RFC1918 (all private IP ranges)
    Protocol: any
    Source: IoT net
    Destination: RFC1918  (192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12)
    Action: Block

  Rule 3: Allow IoT → internet
    Protocol: any
    Source: IoT net
    Destination: any
    Action: Allow

# On the Trusted interface (VLAN 10):
  Allow all (trusted devices can reach everything)
    Source: Trusted net
    Destination: any
    Action: Allow
```

## MikroTik RouterOS Configuration

```
# Step 1: Create a bridge with VLAN filtering enabled
/interface bridge
add name=bridge vlan-filtering=yes

# Step 2: Add physical ports to the bridge
# Trunk port to router/uplink (tagged for all VLANs)
/interface bridge port
add bridge=bridge interface=ether1 frame-types=admit-only-vlan-tagged

# Access port for trusted devices (untagged VLAN 10)
/interface bridge port
add bridge=bridge interface=ether2 pvid=10 frame-types=admit-only-untagged-and-priority-tagged

# Access port for IoT devices (untagged VLAN 20)
/interface bridge port
add bridge=bridge interface=ether3 pvid=20 frame-types=admit-only-untagged-and-priority-tagged

# Step 3: Define which VLANs are allowed on which ports
/interface bridge vlan
add bridge=bridge tagged=ether1 untagged=ether2 vlan-ids=10
add bridge=bridge tagged=ether1 untagged=ether3 vlan-ids=20

# Step 4: Create VLAN interfaces on the bridge (gateway IPs)
/interface vlan
add interface=bridge name=vlan10 vlan-id=10
add interface=bridge name=vlan20 vlan-id=20

# Step 5: Assign gateway IPs
/ip address
add interface=vlan10 address=192.168.10.1/24
add interface=vlan20 address=192.168.20.1/24

# Step 6: DHCP pools and servers
/ip pool
add name=pool-trusted ranges=192.168.10.100-192.168.10.254
add name=pool-iot ranges=192.168.20.100-192.168.20.254

/ip dhcp-server
add interface=vlan10 address-pool=pool-trusted name=dhcp-trusted
add interface=vlan20 address-pool=pool-iot name=dhcp-iot

/ip dhcp-server network
add address=192.168.10.0/24 gateway=192.168.10.1
add address=192.168.20.0/24 gateway=192.168.20.1

# Step 7: Firewall — block IoT from reaching trusted VLAN
/ip firewall filter
add chain=forward src-address=192.168.20.0/24 dst-address=192.168.10.0/24 \
    action=drop comment="Block IoT to Trusted"
```

## Switch Trunk vs Access Ports (appliance-side terminology)

```
# Trunk port: carries multiple VLANs (tagged) — connects switch-to-switch,
#             switch-to-router, switch-to-AP.
# Access port: carries one VLAN (untagged) — connects to end devices
#              (PC, camera, NAS).

# A managed switch port connected to your router should be a trunk:
  Allowed VLANs: 10, 20, 30, 40, 99

# A port connecting to a PC should be an access port:
  VLAN: 10 (trusted)
  No tagging — the PC does not know or care about VLANs

# A port connecting to an AP must be a trunk:
  The AP tags traffic from each SSID with the right VLAN ID
  Allowed VLANs: 10, 20, 40  (whichever SSIDs the AP serves)
```

The equivalent Linux-host-side concept (a NIC receiving a tagged trunk from
one of these switches) is documented in
[`netplan-reference.md` Example 4](netplan-reference.md#bridges-bonds-vlans-wifis).

## Anti-Patterns

```
# BAD: Creating VLANs on the appliance without adding firewall rules
# VLANs alone provide segmentation, not isolation — inter-VLAN routing is
# open by default until explicit block rules exist.
# GOOD: Add explicit block rules immediately after creating VLANs.

# BAD: Native/untagged VLAN equals the management VLAN
# Untagged traffic landing in your management VLAN enables VLAN-hopping
# attacks from any access port.
# GOOD: Use a dedicated, otherwise-unused VLAN as native (e.g. VLAN 999),
# keep management traffic tagged.

# BAD: Same Wi-Fi password for an IoT SSID and a trusted SSID
# Anyone who learns the password can connect IoT devices to the wrong
# segment.
```

## Best Practices

- Start with 4 VLANs: Trusted, IoT, Servers, Guest — add more as needed.
- Put any shared DNS resolver/sinkhole in the Servers VLAN, and add a
  firewall rule allowing DNS (port 53) from all VLANs to it — before any
  RFC1918 block rule.
- Test isolation after every rule change: from the IoT VLAN, try to ping a
  trusted device — it should fail.
- Use a dedicated management VLAN for switch/AP/firewall web UIs and
  restrict access to the Trusted VLAN only.
- Document the VLAN design in a table (VLAN ID, name, subnet, purpose) — see
  the template above.

## See Also

- [`../SKILL.md`](../SKILL.md) — `linux-network-admin`, this reference's
  parent skill; owns the Linux-host side of VLAN configuration.
- [`netplan-reference.md`](netplan-reference.md) — host-side VLAN tagging
  syntax and worked examples (not duplicated here).
- [`../../linux-dns-server/references/pihole-blocklist-sinkholing.md`](../../linux-dns-server/references/pihole-blocklist-sinkholing.md) —
  Pi-hole as the DNS server referenced in the pfSense DHCP/firewall examples
  above.
