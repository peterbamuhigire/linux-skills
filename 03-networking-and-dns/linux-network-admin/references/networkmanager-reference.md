# NetworkManager / nmcli reference (RHEL family)

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

**Netplan does not exist on the RHEL family.** On Fedora, RHEL, CentOS Stream,
Rocky, Alma, and Oracle, persistent network configuration is owned by
**NetworkManager**, driven with **`nmcli`** and stored as keyfiles in
`/etc/NetworkManager/system-connections/`. This is the RHEL-family counterpart
to [`netplan-reference.md`](netplan-reference.md).

The diagnostic layer — `ip`, `ss`, `ping`, `dig`, `resolvectl`,
`traceroute` — is **identical** on both families; only the *persistent config*
tool differs. See [`diagnostics-tree.md`](diagnostics-tree.md).

> Note: `nmcli` also exists on Ubuntu (Netplan can use the NetworkManager
> renderer), but on Ubuntu servers the source of truth is usually Netplan YAML.
> On RHEL the source of truth is NetworkManager itself — edit it with `nmcli`,
> not by hand-writing YAML.

---

## Mental model: connections vs devices

- A **device** is a physical/virtual interface (`eth0`, `ens3`, `wlan0`).
- A **connection** (a.k.a. profile) is a named, persistent config that can be
  activated on a device. One device may have several connection profiles; one
  is active at a time.

```bash
nmcli device status                 # devices and their state
nmcli connection show               # all profiles (active + inactive)
nmcli connection show --active      # only active
nmcli device show ens3              # full detail for one device
nmcli -f IP4 connection show "System ens3"
```

---

## netplan → nmcli translation

| Intent | Netplan (Ubuntu) | nmcli (RHEL family) |
|---|---|---|
| Show config | `cat /etc/netplan/*.yaml` | `nmcli connection show` |
| DHCP on an iface | `dhcp4: true` | `nmcli con add type ethernet ifname ens3 con-name ens3` |
| Static IPv4 | `addresses: [10.0.0.5/24]` | `nmcli con mod ens3 ipv4.addresses 10.0.0.5/24` |
| Gateway | `routes: - to: default via: …` | `nmcli con mod ens3 ipv4.gateway 10.0.0.1` |
| DNS servers | `nameservers: addresses: […]` | `nmcli con mod ens3 ipv4.dns "1.1.1.1 9.9.9.9"` |
| Static method | (implied by addresses) | `nmcli con mod ens3 ipv4.method manual` |
| Dry-run apply | `netplan try` (auto-rollback) | (no exact equal) test then `nmcli con up` |
| Apply | `netplan apply` | `nmcli con up ens3` |
| Config location | `/etc/netplan/*.yaml` | `/etc/NetworkManager/system-connections/*.nmconnection` |

---

## Static IP — full example

```bash
# Create or modify a profile named "ens3" on device ens3
nmcli connection add type ethernet con-name ens3 ifname ens3 \
    ipv4.method manual \
    ipv4.addresses 10.0.0.5/24 \
    ipv4.gateway 10.0.0.1 \
    ipv4.dns "1.1.1.1 9.9.9.9" \
    ipv6.method disabled

# Bring it up (apply)
nmcli connection up ens3

# Verify
ip addr show ens3
ip route
resolvectl status            # or: cat /etc/resolv.conf
```

Modifying an existing profile instead:

```bash
nmcli con mod ens3 ipv4.addresses 10.0.0.6/24
nmcli con mod ens3 +ipv4.dns 8.8.8.8          # append a DNS server
nmcli con mod ens3 ipv4.method manual
nmcli con up ens3                              # re-activate to apply
```

---

## Switch DHCP ⇆ static

```bash
# To DHCP
nmcli con mod ens3 ipv4.method auto
nmcli con mod ens3 ipv4.gateway "" ipv4.addresses "" ipv4.dns ""
nmcli con up ens3

# To static: see the full example above (ipv4.method manual)
```

---

## Routes, VLANs, bonds

```bash
# Extra static route
nmcli con mod ens3 +ipv4.routes "192.168.50.0/24 10.0.0.254"

# VLAN 100 on ens3
nmcli con add type vlan con-name ens3.100 dev ens3 id 100 \
    ipv4.method manual ipv4.addresses 10.100.0.5/24

# Bond (active-backup)
nmcli con add type bond con-name bond0 ifname bond0 mode active-backup
nmcli con add type ethernet con-name bond0-p1 ifname ens4 master bond0
nmcli con add type ethernet con-name bond0-p2 ifname ens5 master bond0
```

---

## Apply / reload / rollback

```bash
nmcli con up <name>            # activate a profile (applies changes)
nmcli con reload               # re-read keyfiles edited on disk
nmcli device reapply ens3      # apply staged changes without full bounce
nmcli networking off && nmcli networking on   # hard reset (careful over SSH)
```

**Over SSH, NetworkManager has no `netplan try` auto-rollback.** Mitigate by
testing in a screen/tmux session, or schedule a safety reset:
`echo 'nmcli networking off && nmcli networking on' | at now + 3 minutes`,
then cancel it once you confirm connectivity.

---

## DNS and time

```bash
# DNS resolution (identical tooling on both families)
resolvectl status
resolvectl query example.com
cat /etc/resolv.conf

# NTP / time sync — chrony is the RHEL default (vs systemd-timesyncd on Ubuntu)
timedatectl
chronyc sources -v          # RHEL family
chronyc tracking
systemctl status chronyd
```

| Time sync | Debian/Ubuntu | RHEL family |
|---|---|---|
| Default daemon | `systemd-timesyncd` | `chronyd` (chrony) |
| Status | `timedatectl`, `timedatectl show-timesync` | `timedatectl`, `chronyc sources` |

---

## References

- [`netplan-reference.md`](netplan-reference.md) — the Debian/Ubuntu counterpart.
- [`diagnostics-tree.md`](diagnostics-tree.md) — `ip`/`ss`/`dig` diagnosis (portable).
- Man pages: `nmcli(1)`, `nm-settings(5)`, `NetworkManager.conf(5)`, `chronyc(1)`.
- Fedora/RHEL docs: "Configuring and managing networking".
