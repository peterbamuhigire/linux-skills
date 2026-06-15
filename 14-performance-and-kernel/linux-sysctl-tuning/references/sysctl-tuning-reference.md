# Sysctl Performance Tuning Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

`[GROUNDING-GAP: sysctl perf tuning (BBR/swappiness/TCP buffers) — kernel Documentation/admin-guide/sysctl + man pages; deepen with Systems Performance 2e (Brendan Gregg)]`

Performance-oriented `net.*`, `vm.*`, and `fs.*` tunables for high-throughput
and connection-heavy servers on both Linux families (Debian/Ubuntu and the RHEL
family — Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). The `sysctl`
interface, the `/etc/sysctl.d/` drop-in mechanism, and `sysctl --system` are
identical across both families; the kernel exposes the same keys.

Every value below is a *starting point* to be justified against a measured
bottleneck, not a blind "ultimate tuning" blob. Tune one axis at a time and
re-measure. For SECURITY sysctl (rp_filter, tcp_syncookies, kptr_restrict,
ICMP/redirect hardening) see the `linux-server-hardening` skill at
[`../../../07-security-and-hardening/linux-server-hardening/references/sysctl-reference.md`](../../../07-security-and-hardening/linux-server-hardening/references/sysctl-reference.md);
keep the two sets in separate drop-in files.

## Table of contents

- [How sysctl is applied and persisted](#how-sysctl-is-applied-and-persisted)
- [Networking throughput](#networking-throughput)
- [BBR congestion control](#bbr-congestion-control)
- [Connection scaling](#connection-scaling)
- [Memory behaviour](#memory-behaviour)
- [File handles](#file-handles)
- [Persistence and verification](#persistence-and-verification)
- [Sources](#sources)

## How sysctl is applied and persisted

A live (transient) change with `sysctl -w` is lost on reboot. Persist by
writing a drop-in under `/etc/sysctl.d/`:

```bash
sysctl net.core.somaxconn                 # read one key
sysctl -a | grep -i congestion            # search the live tree
sudo sysctl -w vm.swappiness=10           # transient, lost on reboot
```

`sysctl --system` reads files in this order, later files overriding earlier:

1. `/etc/sysctl.conf`
2. `/run/sysctl.d/*.conf`
3. `/etc/sysctl.d/*.conf`        ← put your file here
4. `/usr/local/lib/sysctl.d/*.conf`
5. `/usr/lib/sysctl.d/*.conf`
6. `/lib/sysctl.d/*.conf`

Within a directory files sort lexicographically, so a high numeric prefix such
as `60-` or `99-` wins over vendor drop-ins. Never edit `/etc/sysctl.conf`
directly or vendor files in `/usr/lib/sysctl.d/`; own a single drop-in so the
delta is one `cat`, one `diff`, and one `rm` to roll back.

## Networking throughput

For large bandwidth-delay products (10GbE+, long-haul, high-latency links) the
default socket buffer ceilings are too small to fill the pipe. Raise the
ceilings and let TCP autotuning grow the per-socket buffers up to them.

### `net.core.rmem_max` / `net.core.wmem_max`

Maximum receive / send socket buffer size in **bytes** that any socket may
request (via `SO_RCVBUF`/`SO_SNDBUF` and TCP autotuning). These are hard
ceilings, not allocations — memory is only used as connections need it.

```ini
net.core.rmem_max = 134217728   # 128 MiB ceiling
net.core.wmem_max = 134217728
```

Size the ceiling to the bandwidth-delay product: `BDP = bandwidth (bytes/s) ×
RTT (s)`. A 10 Gbit/s link at 100 ms RTT needs roughly 125 MB of in-flight
buffer, hence the 128 MiB figure. On a LAN-only server the defaults are fine.

### `net.ipv4.tcp_rmem` / `net.ipv4.tcp_wmem`

Three values — **min default max** in bytes — that bound TCP's per-socket
autotuning. The kernel grows the buffer from `default` toward `max` as the
connection demands, and shrinks under memory pressure down to `min`. The `max`
here should not exceed `rmem_max`/`wmem_max`.

```ini
net.ipv4.tcp_rmem = 4096 87380 67108864    # min default max (64 MiB max)
net.ipv4.tcp_wmem = 4096 65536 67108864
```

Leave `min` and `default` near their defaults; raising only `max` is the safe
high-throughput change because idle connections still start small.

## BBR congestion control

BBR (Bottleneck Bandwidth and RTT) models the path's bandwidth and RTT instead
of treating loss as congestion. It typically beats CUBIC on lossy or
high-latency paths. BBR's pacing **requires** a pacing-capable qdisc — set the
default qdisc to `fq`.

```ini
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

Verify availability before selecting it — `bbr` must appear in the available
list, otherwise the write fails silently or is rejected:

```bash
sysctl net.ipv4.tcp_available_congestion_control   # must include 'bbr'
sudo modprobe tcp_bbr                               # load the in-tree module if absent
sysctl net.ipv4.tcp_congestion_control              # confirm after apply
```

`tcp_bbr` is in-tree on both families on any reasonably modern kernel; only the
module needs loading. Pairing BBR with `fq` is not optional — without `fq`
(or `fq_codel` with pacing) BBR cannot pace and loses much of its benefit.

## Connection scaling

For servers handling many concurrent or short-lived connections.

### `net.core.somaxconn`

Upper bound on the kernel's accept queue — the completed-handshake connections
waiting for the application to `accept()`. This only **caps** the queue; the
application's `listen()` backlog argument must be raised to actually use it
(e.g. nginx `listen 443 backlog=65535;`).

```ini
net.core.somaxconn = 65535
```

### `net.ipv4.tcp_max_syn_backlog`

Size of the half-open (SYN_RECV) queue — connections mid-handshake. Raise it
on a connection-burst server so legitimate handshakes are not dropped under
load.

```ini
net.ipv4.tcp_max_syn_backlog = 8192
```

### `net.ipv4.tcp_fin_timeout`

Seconds an orphaned connection stays in FIN-WAIT-2 before being forcibly
closed. The default is 60; lowering to 30 frees socket state faster on a busy
server that opens and closes many connections.

```ini
net.ipv4.tcp_fin_timeout = 30
```

### Supporting keys

```ini
net.core.netdev_max_backlog = 16384        # per-CPU ingress packet queue
net.ipv4.ip_local_port_range = 1024 65535  # ephemeral ports for outbound
net.ipv4.tcp_tw_reuse = 1                  # reuse TIME_WAIT sockets for new outbound
```

`tcp_tw_reuse=1` is safe since kernel 4.12 (the TCP timestamp check keeps it
protocol-compliant) and helps hosts that make many outbound connections exhaust
fewer ephemeral ports.

## Memory behaviour

### `vm.swappiness`

How aggressively the kernel swaps anonymous pages versus reclaiming page cache
(range 0–200, default 60). Lower keeps the working set in RAM and favours the
page cache.

```ini
vm.swappiness = 10
```

**Do not set 0.** `0` disables swapping of anonymous memory almost entirely
and can push the box into the OOM killer under pressure when a little swap
would have saved it. `10` (sometimes `1`) is the safe low value.

### `vm.dirty_ratio` / `vm.dirty_background_ratio`

Percentage of RAM that may hold dirty (unwritten) pages before, respectively, a
writing process is **blocked** to flush synchronously (`dirty_ratio`) and the
kernel starts flushing **asynchronously** in the background
(`dirty_background_ratio`). `dirty_background_ratio` must be lower than
`dirty_ratio`.

```ini
vm.dirty_ratio = 20            # writers block at 20% RAM dirty
vm.dirty_background_ratio = 5  # async flush starts at 5%
```

Lower values smooth out I/O and reduce write-stall latency spikes on
write-heavy or latency-sensitive workloads; the defaults (often 20/10) favour
throughput. On large-RAM hosts the percentage-based defaults can buffer many
gigabytes — consider the byte-valued `vm.dirty_bytes`/`vm.dirty_background_bytes`
instead if you need a fixed cap.

### `vm.overcommit_memory`

How the kernel handles memory-allocation requests:

- `0` — heuristic overcommit (default). Allows reasonable overcommit, refuses
  obviously absurd requests. Correct for most servers; MySQL and PHP expect it.
- `1` — always overcommit. Required by Redis to fork for background saves
  without a fork failure; only set on Redis-dedicated hosts.
- `2` — strict accounting: total commit capped at swap + `overcommit_ratio`% of
  RAM. Prevents the OOM killer but causes `malloc` to fail early; use only when
  you have deliberately accepted that trade-off.

```ini
vm.overcommit_memory = 0
```

## File handles

### `fs.file-max`

System-wide ceiling on the number of open file descriptors the kernel will
allocate. A connection-heavy server (each socket is an fd) can exhaust the
default. This is the kernel cap; per-process limits via `ulimit -n` /
`LimitNOFILE=` in a systemd unit must also be raised to benefit.

```ini
fs.file-max = 2097152
```

Check current usage with `cat /proc/sys/fs/file-nr` (allocated, unused, max).

## Persistence and verification

Write one owned drop-in with a high prefix, then apply and re-read:

```bash
sudo tee /etc/sysctl.d/60-perf.conf >/dev/null <<'EOF'
# /etc/sysctl.d/60-perf.conf — performance tuning (linux-sysctl-tuning)
# Apply with: sudo sysctl --system ; remove this file to roll back.

# --- Networking throughput ---
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# --- BBR (requires fq qdisc) ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# --- Connection scaling ---
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_fin_timeout = 30
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_tw_reuse = 1

# --- Memory ---
vm.swappiness = 10
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5
vm.overcommit_memory = 0

# --- File handles ---
fs.file-max = 2097152
EOF

sudo sysctl --system          # apply ALL drop-ins
```

Verify each key took the new value by re-reading it — `sysctl --system` does
not error if a key name is misspelled in some versions, so confirm explicitly:

```bash
sysctl net.core.somaxconn net.ipv4.tcp_congestion_control vm.swappiness
sysctl net.core.rmem_max net.ipv4.tcp_rmem fs.file-max
tc qdisc show dev eth0        # confirm fq is the active qdisc for BBR
cat /proc/sys/fs/file-nr      # allocated / unused / max fds
```

Roll back by deleting the single drop-in and reapplying:

```bash
sudo rm /etc/sysctl.d/60-perf.conf
sudo sysctl --system
```

Keep performance keys here and SECURITY keys in `linux-server-hardening`'s
drop-in — never mix the two in one file, so each set has clear ownership.

## Sources

- Linux kernel documentation: `Documentation/admin-guide/sysctl/net.rst`,
  `vm.rst`, and `fs.rst`; `Documentation/networking/ip-sysctl.rst`.
- Man pages: `tcp(7)`, `socket(7)`, `sysctl(8)`, `sysctl.d(5)`, `tc(8)`,
  `tc-fq(8)`, `proc(5)` (`/proc/sys/...`).
- Neal Cardwell et al., "BBR: Congestion-Based Congestion Control"
  (ACM Queue, 2016) — the BBR design and its dependence on packet pacing.
- *Systems Performance: Enterprise and the Cloud*, 2nd Edition, Brendan Gregg
  — networking and memory tuning methodology (recommended to deepen the
  grounding gap flagged above).
