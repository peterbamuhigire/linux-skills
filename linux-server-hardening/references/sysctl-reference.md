# Sysctl Reference — Production Tunables

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Every sysctl worth setting on a production Ubuntu/Debian web server, with
the safe production value, the threat it mitigates, and where it lives.
All settings go in a single file — `/etc/sysctl.d/99-linux-skills.conf` —
so the entire hardening delta is one `cat`, one `diff`, and one `rm` to
roll back. A complete copy-pasteable file is at the end.

## Table of contents

- [How sysctl is applied](#how-sysctl-is-applied)
- [Kernel hardening](#kernel-hardening)
- [Filesystem / core-dump hygiene](#filesystem--core-dump-hygiene)
- [Network stack — IPv4](#network-stack--ipv4)
- [Network stack — IPv6](#network-stack--ipv6)
- [TCP tuning for small web servers](#tcp-tuning-for-small-web-servers)
- [Memory](#memory)
- [What NOT to set](#what-not-to-set)
- [Complete 99-linux-skills.conf](#complete-99-linux-skillsconf)
- [Applying and testing](#applying-and-testing)
- [Sources](#sources)

## How sysctl is applied

`sysctl --system` reads files in this order, with later files overriding:

1. `/etc/sysctl.conf`
2. `/run/sysctl.d/*.conf`
3. `/etc/sysctl.d/*.conf`
4. `/usr/local/lib/sysctl.d/*.conf`
5. `/usr/lib/sysctl.d/*.conf`
6. `/lib/sysctl.d/*.conf`

Within a directory, files sort lexicographically so `99-linux-skills.conf`
always wins. Each setting is an ordinary key=value; comments start with
`#`. Apply immediately with `sudo sysctl --system`. Nothing here requires
a reboot.

## Kernel hardening

These settings reduce the information available to a local exploit and
restrict privileged kernel interfaces.

### `kernel.randomize_va_space = 2`

Full address-space layout randomization for stack, VDSO, shared memory,
heap, and executable. Setting `0` disables ASLR entirely; `1` is partial
(no heap randomization). **Always `2` in production.** Mitigates
return-oriented programming and exploit reliability.

### `kernel.dmesg_restrict = 1`

Restrict `dmesg` output to root. Kernel messages routinely include kernel
pointer addresses, stack frames, and module load details that accelerate
exploit development. The cost is that non-root users running the
userspace `dmesg` command see "Operation not permitted"; this has no
impact on a web server.

### `kernel.kptr_restrict = 2`

Hide kernel symbol addresses from `/proc/kallsyms` and related files.
Values:
- `0` — no restriction (pre-hardened default on some distros).
- `1` — non-root sees `0000000000000000` instead of real addresses.
- `2` — everyone sees `0000000000000000` regardless of privilege.
Value `2` is safe on servers; use `1` only on hosts that run debuggers.

### `kernel.yama.ptrace_scope = 1`

Restrict `ptrace` to parent processes only. Values:
- `0` — any process with the same UID can ptrace another.
- `1` — only direct parent, or after `prctl(PR_SET_PTRACER)`.
- `2` — only root (via `CAP_SYS_PTRACE`).
- `3` — ptrace disabled entirely until reboot.
Value `1` breaks nothing in practice; value `2` can break debuggers and
`gdb`. Mitigates lateral movement between processes of the same user
after an RCE.

### `kernel.sysrq = 0`

Disable the Magic SysRq key. On a server with no physical keyboard, SysRq
is useless but is also a local DoS vector if the box ever gets one. `0`
fully disables it; `438` is the popular middle-ground for laptops.

### `kernel.unprivileged_bpf_disabled = 1`

Require `CAP_BPF` or `CAP_SYS_ADMIN` to load eBPF programs. Unprivileged
eBPF has been a source of high-severity CVEs (CVE-2021-3490, CVE-2022-23222).
A web server has no legitimate need for unprivileged users to load BPF.

### `kernel.perf_event_paranoid = 3`

Restrict `perf_event_open` to root only. Ubuntu's default is `2`; setting
`3` closes an attack surface that has produced multiple LPE CVEs.

### `kernel.kexec_load_disabled = 1`

Disable loading a new kernel via `kexec_load` after boot. Blocks a root
attacker from pivoting into a crafted kernel without touching GRUB. Once
set, it cannot be unset until reboot.

### `kernel.modules_disabled = 1` — **use only on hardened kiosks**

Block all kernel module loads after boot. This is very aggressive — you
cannot load a new driver without rebooting. Leave **unset** on
general-purpose servers; set it on appliance hosts that never need new
modules.

## Filesystem / core-dump hygiene

### `fs.suid_dumpable = 0`

SUID binaries do not generate core dumps. A SUID crash that dumps core
leaks memory that may contain credentials or kernel pointers.

### `fs.protected_symlinks = 1`

Prevent symlink following unless the follower is the owner of the link,
or the link and the enclosing directory have matching owners. Blocks a
classic shared-directory attack where an attacker plants `/tmp/root.txt
-> /etc/shadow` and waits for a privileged process to read it.

### `fs.protected_hardlinks = 1`

Prevent hardlink creation unless the user owns the target or can read it.
Same class of attack, mitigated in `/tmp`.

### `fs.protected_fifos = 2` and `fs.protected_regular = 2`

Prevent opening FIFOs and regular files in world-writable sticky
directories (`/tmp`, `/var/tmp`) unless the opener owns them or the file.
Mitigates spoofing and race-condition attacks against privileged helpers.

## Network stack — IPv4

### `net.ipv4.tcp_syncookies = 1`

Enable SYN cookies. Under a SYN flood, the kernel stops allocating
socket state per SYN and instead encodes the state into a cryptographic
cookie returned as the SYN/ACK sequence number. This is the single most
impactful DoS mitigation on the box. Always on.

### `net.ipv4.conf.all.rp_filter = 1` and `default.rp_filter = 1`

Reverse-path filtering (strict mode). Drops packets whose source address
is not reachable through the interface they arrived on. Blocks most IP
spoofing attempts against single-homed servers. If this box is a router
with asymmetric routing, use `2` (loose) instead — not `0`.

### `net.ipv4.conf.all.accept_redirects = 0` and `default.accept_redirects = 0`

Ignore ICMP redirect messages. ICMP redirects were designed so routers
could tell hosts about better paths, but on a server they are pure MITM
vector. Set to `0` on both `all` and `default` (and the same for IPv6).

### `net.ipv4.conf.all.secure_redirects = 0`

Even "secure" redirects (from the current default gateway) are turned
off. A compromised upstream router should not be able to change this
box's routing.

### `net.ipv4.conf.all.send_redirects = 0` and `default.send_redirects = 0`

Don't emit ICMP redirects. Only routers should send them; a web server
has no business doing so.

### `net.ipv4.conf.all.accept_source_route = 0` and `default.accept_source_route = 0`

Reject source-routed packets. Source routing lets a sender pick the path
the reply takes and is almost exclusively used to bypass firewall rules.

### `net.ipv4.conf.all.log_martians = 1` and `default.log_martians = 1`

Log packets with impossible source addresses ("martians"). These show up
in `dmesg` / `kern.log` and are a useful low-volume IDS signal.

### `net.ipv4.icmp_echo_ignore_broadcasts = 1`

Ignore ICMP broadcast echo requests. Mitigates Smurf-style amplification.

### `net.ipv4.icmp_ignore_bogus_error_responses = 1`

Silently drop bogus ICMP error responses — reduces log noise and a small
amount of DoS exposure.

### `net.ipv4.tcp_rfc1337 = 1`

Drop RST packets for sockets in the `TIME_WAIT` state. Mitigates the
TIME_WAIT assassination attack described in RFC 1337 ("`TIME_WAIT`
Assassination Hazards").

### `net.ipv4.icmp_echo_ignore_all = 0`

**Leave as 0** — do not blanket-disable ICMP echo. Pingability is a
diagnostic feature you will want for troubleshooting; the DoS mitigation
is negligible.

## Network stack — IPv6

Same defense pattern as IPv4. Apply both `all` and `default`:

### `net.ipv6.conf.all.accept_redirects = 0` / `default.accept_redirects = 0`

Same reasoning as IPv4.

### `net.ipv6.conf.all.accept_source_route = 0` / `default.accept_source_route = 0`

Same reasoning as IPv4.

### `net.ipv6.conf.all.accept_ra = 0` / `default.accept_ra = 0`

Ignore IPv6 Router Advertisements. On a statically-configured server
behind a known router, RAs are unnecessary and a vector for rogue routers.

### `net.ipv6.conf.all.forwarding = 0`

Disable forwarding unless the box is intentionally a router. A laptop-
turned-proxy with forwarding on is a common accidental misconfiguration.

### `net.ipv6.conf.all.disable_ipv6 = 0`

**Leave as 0.** Do not disable IPv6 wholesale — many modern sites need
it, and Nginx will happily bind `::` for dual-stack. Use firewall rules
to limit v6 exposure instead.

## TCP tuning for small web servers

These are not strictly security tunables but they interact with DoS
resilience and are worth setting on production.

### `net.ipv4.tcp_max_syn_backlog = 4096`

Queue more half-open connections before dropping. Pair with
`tcp_syncookies=1` for the full SYN-flood mitigation.

### `net.core.somaxconn = 4096`

Upper bound on the listen backlog (`listen(2)` queue). Nginx caps its
own backlog to this, so if you raise `listen 443 backlog=4096;` in
Nginx you need to raise this too.

### `net.ipv4.tcp_fin_timeout = 30`

How long an orphaned FIN-WAIT-2 socket waits before being closed.
Default is 60; 30 is safer under a slow-drain attack.

### `net.ipv4.tcp_keepalive_time = 300`

Start keepalives after 5 min of idle. Helps detect half-open sockets
from dead clients faster and frees resources.

### `net.ipv4.tcp_tw_reuse = 1`

Reuse sockets in `TIME_WAIT` state for new outgoing connections. Safe
since kernel 4.12 where the TCP timestamp check makes this protocol-
compliant. Helps hosts that make many outbound HTTP calls.

## Memory

### `vm.swappiness = 10`

Prefer keeping working set in RAM; swap only when necessary. On a
dedicated MySQL/PHP server this prevents swap thrashing under pressure.
`0` is too aggressive (disables swapping even when it would help);
`10`–`20` is the sweet spot.

### `vm.overcommit_memory = 0`

Default heuristic overcommit. Leave unchanged; Redis and MySQL expect it.
`1` (always allow) is only correct for Redis-dedicated hosts where you
have manually accepted the trade-off.

### `vm.min_free_kbytes`

Usually auto-tuned by the kernel based on RAM. Don't set it unless you
have a specific reason — mis-setting this breaks OOM behavior.

## What NOT to set

Tunables commonly found in old hardening guides that are either
counterproductive or have been superseded:

- `net.ipv4.tcp_timestamps = 0` — disables RFC 1323 PAWS, hurts
  throughput, and the "uptime fingerprinting" mitigation is not worth
  the cost.
- `net.ipv4.icmp_echo_ignore_all = 1` — breaks diagnostics, negligible
  security benefit.
- `net.ipv4.tcp_sack = 0` — disables selective ACK, hurts throughput on
  lossy links. Was proposed after SACK CVEs (CVE-2019-11477) but those
  were patched years ago.
- `net.ipv6.conf.all.disable_ipv6 = 1` — breaks too much modern tooling.
- `kernel.exec-shield = 1` — legacy, ignored on modern kernels.
- `net.ipv4.conf.all.arp_ignore = 1` without understanding what it does
  — it can break L2 reachability.

## Complete 99-linux-skills.conf

Paste this whole block into `/etc/sysctl.d/99-linux-skills.conf`:

```ini
# /etc/sysctl.d/99-linux-skills.conf
# Production hardening baseline for Ubuntu/Debian web servers.
# Apply with: sudo sysctl --system
# Managed by linux-server-hardening — remove this file to roll back.

# --- Kernel hardening ------------------------------------------------
kernel.randomize_va_space = 2
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 1
kernel.sysrq = 0
kernel.unprivileged_bpf_disabled = 1
kernel.perf_event_paranoid = 3
kernel.kexec_load_disabled = 1

# --- Filesystem / core-dump hygiene ----------------------------------
fs.suid_dumpable = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2

# --- IPv4 network hardening ------------------------------------------
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# --- IPv6 network hardening ------------------------------------------
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
net.ipv6.conf.all.forwarding = 0

# --- TCP tuning for small web servers --------------------------------
net.ipv4.tcp_max_syn_backlog = 4096
net.core.somaxconn = 4096
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_tw_reuse = 1

# --- Memory ----------------------------------------------------------
vm.swappiness = 10
```

## Applying and testing

```bash
# Apply
sudo sysctl --system

# Verify a few key values
sysctl kernel.randomize_va_space kernel.kptr_restrict net.ipv4.tcp_syncookies

# Watch all sysctls that differ from defaults (requires sysctl-explorer or careful diff)
sudo sysctl -a 2>/dev/null | sort > /tmp/sysctl.now
# diff against /tmp/sysctl.pre-hardening captured earlier

# If something breaks, remove the file and reapply
sudo rm /etc/sysctl.d/99-linux-skills.conf
sudo sysctl --system
```

Per-interface settings from `all` do **not** propagate to interfaces
brought up after the sysctl apply — Ubuntu's `systemd-sysctl` fixes this
by reapplying on network events, but if you ever add an interface mid-
flight run `sudo sysctl --system` again.

## Sources

- *Mastering Linux Security and Hardening*, Donald A. Tevault, 3rd
  Edition, Packt — Chapter 11 "Kernel Hardening and Process Isolation":
  setting parameters with `sysctl`, configuring `sysctl.conf`.
- *Practical Linux Security Cookbook*, Tajinder Kalsi, Packt — kernel
  and network hardening recipes (TCP SYN cookies, rp_filter, ICMP).
- *Ubuntu Server Guide*, Canonical — "Security" chapter networking and
  kernel tuning appendix.
- CIS Ubuntu 22.04 LTS Benchmark (Level 1 Server) — the exact values
  here match the benchmark's recommended settings where both specify a
  value.
- Linux kernel documentation: `Documentation/admin-guide/sysctl/*.txt`
  (kernel.txt, net.txt, fs.txt, vm.txt).
- RFC 1337 — "TIME_WAIT Assassination Hazards in TCP".
