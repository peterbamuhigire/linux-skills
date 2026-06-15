# Packet capture & process/file tracing

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Two related deep-dives that the diagnosis tree refers to:

1. **Network packet capture** with `tcpdump` — "is the traffic even
   arriving / leaving, and what does it look like on the wire?"
2. **Process & file diagnostics** with `strace` / `ltrace` / `lsof` — "why
   is this process hung, and what is holding this file or this port?"

Both work on a stock Debian/Ubuntu **and** RHEL-family server. The tools live
in slightly different packages per family (see the install table below), but
the commands themselves are identical across families.

> [GROUNDING-GAP: strace/ltrace/lsof/tcpdump — grounded on man pages and *The
> Linux Programming Interface* (Kerrisk); deepen on purchase]

## Installing the tools

| Tool | Debian/Ubuntu | RHEL family |
|---|---|---|
| `tcpdump` | `apt install tcpdump` | `dnf install tcpdump` |
| `tshark` (CLI Wireshark) | `apt install tshark` | `dnf install wireshark-cli` |
| `strace` | `apt install strace` | `dnf install strace` |
| `ltrace` | `apt install ltrace` | `dnf install ltrace` |
| `lsof` | `apt install lsof` | `dnf install lsof` |

`lsof` is usually preinstalled on both families; `tcpdump` and `strace` often
are too. `ltrace` is the one most likely missing — install on demand.

---

## Table of contents

- [Part 1 — Network packet capture (tcpdump)](#part-1--network-packet-capture-tcpdump)
  - [Pick the interface](#pick-the-interface)
  - [The basic capture](#the-basic-capture)
  - [BPF filters: host / port / proto](#bpf-filters-host--port--proto)
  - [Snaplen — capture less per packet](#snaplen--capture-less-per-packet)
  - [Write and read pcap (`-w` / `-r`)](#write-and-read-pcap--w---r)
  - [Ring buffers for long captures (`-C` / `-W` / `-G`)](#ring-buffers-for-long-captures--c---w---g)
  - [Diagnosing common wire-level faults](#diagnosing-common-wire-level-faults)
  - [Offline analysis: tshark / Wireshark](#offline-analysis-tshark--wireshark)
- [Part 2 — Process & file diagnostics (strace / ltrace / lsof)](#part-2--process--file-diagnostics-strace--ltrace--lsof)
  - [Decision: which tool?](#decision-which-tool)
  - [lsof — what holds this file or port](#lsof--what-holds-this-file-or-port)
  - [strace — syscall trace](#strace--syscall-trace)
  - [ltrace — library-call trace](#ltrace--library-call-trace)
  - [Workflow: why is this process hung?](#workflow-why-is-this-process-hung)
- [Sources](#sources)

---

## Part 1 — Network packet capture (tcpdump)

`tcpdump` answers the question logs cannot: **is the packet actually on the
wire, and what is in it?** Use it when a service "should" be reachable but
isn't — to distinguish *traffic never arrives* (firewall/routing) from
*arrives but the server never answers* (app/listen problem) from *answers but
the client never sees it* (return-path/routing).

`tcpdump` needs `CAP_NET_RAW` — run with `sudo`.

### Pick the interface

```bash
sudo tcpdump -D                 # list capturable interfaces
ip -br addr                     # which iface has the IP you care about
sudo tcpdump -i any ...         # 'any' captures on all interfaces (Linux)
```

`-i any` is the safest default when you do not yet know which interface the
traffic uses. Once you know, name it (`-i eth0`) to cut noise.

### The basic capture

```bash
# Show packets, don't resolve names/ports (-n), be verbose (-v), one per line
sudo tcpdump -i any -nn -v port 443

# -nn  : no DNS and no port-name resolution (faster, unambiguous)
# -e   : also print link-layer (MAC) header — useful for ARP/L2 problems
# -c N : stop after N packets (always bound an interactive capture)
# -tttt: human-readable absolute timestamps
sudo tcpdump -i eth0 -nn -c 20 -tttt host 10.0.0.5
```

Always pass `-c` (or a ring-buffer limit, below) so an interactive capture
cannot run away and fill the terminal — or the disk, when writing to a file.

### BPF filters: host / port / proto

The filter expression is a Berkeley Packet Filter — the kernel drops
non-matching packets before they ever reach userspace, so a tight filter is
both cleaner and cheaper.

```bash
# By host (source OR destination)
sudo tcpdump -nn host 192.168.1.50
sudo tcpdump -nn src host 192.168.1.50      # only as source
sudo tcpdump -nn dst host 192.168.1.50      # only as destination

# By port
sudo tcpdump -nn port 3306                  # MySQL, either direction
sudo tcpdump -nn dst port 80

# By protocol
sudo tcpdump -nn icmp                        # pings / unreachables
sudo tcpdump -nn tcp
sudo tcpdump -nn udp port 53                 # DNS

# By network/CIDR
sudo tcpdump -nn net 10.0.0.0/24

# Combine with and / or / not (quote so the shell leaves them alone)
sudo tcpdump -nn 'host 10.0.0.5 and tcp port 443'
sudo tcpdump -nn 'port 80 or port 443'
sudo tcpdump -nn 'tcp and not port 22'       # exclude your own SSH session

# Match TCP flags — only SYN packets, or only SYN-ACK
sudo tcpdump -nn 'tcp[tcpflags] & tcp-syn != 0'
sudo tcpdump -nn 'tcp[tcpflags] & (tcp-syn|tcp-ack) == (tcp-syn|tcp-ack)'
```

> Tip: always `not port 22` (or `not host <your-ip>`) when capturing remotely,
> or your own SSH traffic floods the capture and feeds back on itself.

### Snaplen — capture less per packet

By default modern `tcpdump` captures the whole packet (snaplen 262144). When
you only need headers (connection-level debugging), cap it with `-s` to reduce
load and file size:

```bash
sudo tcpdump -i any -s 96 -nn port 443       # first 96 bytes = L2/L3/L4 headers
sudo tcpdump -i any -s 0 -nn port 443        # 0 = full packet (explicit default)
```

Use a small snaplen for "is the handshake happening?" questions; use full
snaplen when you need to see payload (TLS SNI, HTTP request lines, etc.).

### Write and read pcap (`-w` / `-r`)

Capturing to a file is the right move for anything you want to analyze
carefully or hand to someone else (Wireshark). `-w` writes raw pcap; the
console stays quiet so capture is cheap.

```bash
# Capture to a pcap file (binary, NOT human-readable)
sudo tcpdump -i any -nn -w /tmp/capture.pcap port 443

# Read it back later (no root needed to read a file you own)
tcpdump -nn -r /tmp/capture.pcap
tcpdump -nn -r /tmp/capture.pcap 'host 10.0.0.5 and tcp'   # re-filter offline
```

You can re-apply a *different* BPF filter at read time, so capture broadly to
disk once, then slice it many ways without re-capturing.

### Ring buffers for long captures (`-C` / `-W` / `-G`)

To capture for hours/days without filling the disk, rotate files. Combine
size- or time-based rotation with a fixed file count so total disk use is
bounded.

```bash
# Rotate at 100 MB per file, keep 10 files (max ~1 GB total), then overwrite oldest
sudo tcpdump -i any -nn -w /var/log/cap/trace.pcap -C 100 -W 10 port 443

# -C SIZE : start a new file every SIZE *megabytes*
# -W N    : keep at most N files (ring); also zero-pads the filename suffix
# -G SECS : rotate on a time interval instead of size (often with strftime in -w)
sudo tcpdump -i any -nn -G 3600 -W 24 -w '/var/log/cap/trace-%Y%m%d-%H%M.pcap'
```

`-G` plus a `strftime`-templated `-w` name gives you one file per hour with a
timestamped name — ideal for "catch the intermittent failure overnight."
Always bound the ring (`-W`) so the capture cannot exhaust the disk; a runaway
capture is itself a Branch-3 (disk full) incident.

### Diagnosing common wire-level faults

**SYN but no SYN-ACK** — the classic "connection times out / refused":

```bash
sudo tcpdump -i any -nn "tcp port <PORT> and host <CLIENT>"
```

- You see the client's **SYN** but **no SYN-ACK** back →
  - packet reaches the server but nothing is listening, or a firewall on the
    server dropped it silently → check `ss -tlnp | grep :<PORT>`,
    `firewall-cmd --list-all` / `ufw status`, and (RHEL) SELinux port labels.
  - You see *no SYN at all* on the server → it never arrived → upstream
    firewall / routing / wrong interface.
- You see **SYN → RST** (reset) → port is closed / service down → Branch 4.
- You see SYN-ACK leave the server but the client reports a timeout → the
  **return path** is broken (asymmetric routing, NAT, client-side firewall).

**Routing loops / TTL exhaustion:**

```bash
sudo tcpdump -i any -nn -v icmp        # watch for 'time exceeded in-transit'
```

Repeated ICMP `time exceeded` for the same flow, or the same packet seen
bouncing between two interfaces, points at a routing loop. Cross-check with
`ip route get <dst>` and `traceroute <dst>` (which uses TTL the same way).

**Dropped packets (by the capture itself):**

When `tcpdump` exits it prints `N packets dropped by kernel`. That means the
capture could not keep up (filter too broad, snaplen too large, disk too slow
for `-w`) — **the drops are in the tool, not necessarily on the network.**
Tighten the BPF filter, lower the snaplen (`-s 96`), or write to a faster disk.
True *network* drops show up instead as retransmissions: in Wireshark/tshark
look for `tcp.analysis.retransmission`.

### Offline analysis: tshark / Wireshark

For anything beyond eyeballing headers, capture to pcap with `tcpdump -w` and
open it in **Wireshark** (GUI, on your workstation — never install a GUI on a
production server) or **tshark** (Wireshark's CLI) on the box itself:

```bash
# Read a pcap with Wireshark's dissectors and display filters (-Y)
tshark -r /tmp/capture.pcap -Y 'http.request'
tshark -r /tmp/capture.pcap -Y 'tcp.analysis.retransmission'
tshark -r /tmp/capture.pcap -q -z conv,tcp        # TCP conversation summary

# tshark can also capture live, but on a server prefer tcpdump -w then analyze
```

Wireshark's **display filters** (`-Y`, dotted syntax like `http.request`) are
*not* the same as `tcpdump`'s **BPF capture filters** (`port 80`) — display
filters run after dissection and are far richer. Capture broad with tcpdump,
filter rich with tshark/Wireshark.

The fast-path helper [`sk-capture`](#sources) wraps a safe, bounded
`tcpdump -w` (it forces a packet/size limit and confirms before writing).

---

## Part 2 — Process & file diagnostics (strace / ltrace / lsof)

When a process is **hung**, **spinning**, or **can't open something**, these
three tools answer different layers of the same question:

- **`lsof`** — what files / sockets / ports does this process *hold*, and who
  holds *this* file or port? (no trace, just current state)
- **`strace`** — what **system calls** is it making, and which are failing or
  blocking? (kernel boundary)
- **`ltrace`** — what **library calls** is it making? (application boundary,
  above syscalls)

### Decision: which tool?

| Question | Tool |
|---|---|
| "What port/file is this process using?" or "who has port 8080 / this file open?" | `lsof` |
| "Why can't it open/find a file? Why ECONNREFUSED? Where is it blocked?" | `strace` |
| "It's not a syscall — which library function returns the wrong thing?" | `ltrace` |
| "Disk still full after deleting a big log" | `lsof` (deleted-but-open) |

### lsof — what holds this file or port

```bash
# Who is listening on / connected to a port
sudo lsof -i :8080                    # any proto on port 8080
sudo lsof -iTCP:443 -sTCP:LISTEN      # only the TCP listener on 443
sudo lsof -i -P -n                    # all network files, numeric (-P ports, -n no DNS)

# Everything a process has open, by PID
sudo lsof -p <PID>

# Who has a specific file / device open (e.g. before unmounting)
sudo lsof /var/log/app.log
sudo lsof /mnt/data                   # what blocks `umount /mnt/data`?

# Everything open *under a directory* (recursive)
sudo lsof +D /var/www                 # +D descends; +d is one level only

# Files open by a user
sudo lsof -u www-data
```

**Deleted-but-open files (disk full after `rm`):** a process holding an open
fd to a deleted file keeps the space allocated until it closes — `df` shows
full, `du` shows little. Find the culprit:

```bash
sudo lsof -nP +L1                     # +L1 = link count < 1, i.e. deleted-but-open
sudo lsof | grep -i deleted
```

The fix is to restart (or signal to reopen) the process holding the deleted
file — *not* another `rm`. This is the #1 "I deleted the logs but disk is still
full" cause (see Branch 3).

### strace — syscall trace

```bash
# Trace a command from launch (very noisy without a filter)
strace <cmd>

# Attach to a running process (the production case)
sudo strace -p <PID>

# Follow forked children too — essential for pre-fork servers (Apache, PHP-FPM)
sudo strace -f -p <MASTER-PID>

# Filter to a class of syscalls (huge signal-to-noise win)
strace -e trace=file    <cmd>         # open/stat/unlink/...   "what file is missing?"
strace -e trace=network <cmd>         # socket/connect/bind/... "who can't it reach?"
strace -e trace=openat,connect -f -p <PID>

# Time each syscall (-T) and show a summary table (-c)
sudo strace -T -p <PID>               # -T appends <elapsed> to each call → find the slow one
strace -c -f <cmd>                    # -c = no per-call output, just a totals table at the end

# Capture to a file instead of the terminal
sudo strace -f -tt -T -o /tmp/trace.out -p <PID>
```

Read the trace for the failing or blocking call:

- `openat(..., O_RDONLY) = -1 ENOENT (No such file or directory)` → missing
  file / wrong path.
- `... = -1 EACCES (Permission denied)` → permissions, or **SELinux/AppArmor**
  (the syscall is denied even though unix perms look fine — RHEL family,
  cross-check `ausearch -m AVC`).
- `connect(..., ...) = -1 ECONNREFUSED` → upstream service down / wrong port.
- A `read()`, `futex()`, `poll()`, or `accept()` that **never returns** (the
  trace just stops) → that is where it is hung. `-T` shows which call is
  eating the wall-clock time.
- `-c` summary with one syscall dominating `% time` → that subsystem is the
  bottleneck.

`strace` adds significant overhead — never leave it attached to a hot
production process longer than needed; capture a few seconds with `-o` and
detach (Ctrl-C, or it detaches when the traced process exits).

### ltrace — library-call trace

`ltrace` traces dynamic-library calls (e.g. `malloc`, `getenv`,
`SSL_connect`, `mysql_query`) rather than syscalls. Use it when the bug is in
*how the app uses a library*, not at the kernel boundary:

```bash
ltrace <cmd>
ltrace -S <cmd>                       # -S also shows syscalls (ltrace + strace view)
sudo ltrace -p <PID>
ltrace -c <cmd>                       # summary: which library calls dominate
ltrace -e 'malloc+free' <cmd>         # filter to specific functions
```

`ltrace` is higher-overhead and less reliable on statically-linked or stripped
binaries than `strace` — reach for `strace` first, `ltrace` when you
specifically suspect a library-level misuse.

### Workflow: why is this process hung?

1. **Confirm the state.** `ps -o pid,stat,wchan:32,cmd -p <PID>` — `STAT`
   shows `D` (uninterruptible I/O wait), `S`/`Sl` (sleeping), `R` (running/
   spinning), `Z` (zombie); `wchan` names the kernel function it's parked in.
2. **What does it hold?** `sudo lsof -p <PID>` — open files, sockets, the port
   it's bound to, any deleted-but-open file.
3. **What is it doing right now?** `sudo strace -f -T -p <PID>` for a few
   seconds:
   - stuck in `read`/`poll`/`accept` with no return → blocked waiting on a peer
     or fd → follow that fd back via step 2's `lsof`.
   - looping over the same failing syscall → it's spinning on an error
     (e.g. retrying a `connect` that gets `ECONNREFUSED`).
   - nothing prints at all → fully blocked in the kernel; `STAT D` + `wchan`
     from step 1 tells you on what (disk, NFS, lock).
4. **If syscalls look fine but behavior is wrong** → `ltrace -p <PID>` to see
   the library-level logic.
5. **Locked file / port?** `sudo lsof <file>` or `sudo lsof -i :<port>` names
   the *other* process holding it — often the real culprit (a stale process
   holding the port a new one can't bind, a writer holding a lock).

---

## Sources

- Man pages: `tcpdump(1)`, `pcap-filter(7)`, `tshark(1)`, `strace(1)`,
  `ltrace(1)`, `lsof(8)`, `ss(8)`, `ip-route(8)`.
- Book: *The Linux Programming Interface* (Michael Kerrisk) — system calls,
  file descriptors, and sockets (background for `strace`/`lsof` reading).
- The `sk-capture` fast-path script (this skill's manifest) wraps a bounded,
  confirmed `tcpdump -w` capture.

> [GROUNDING-GAP: strace/ltrace/lsof/tcpdump — grounded on man pages and *The
> Linux Programming Interface* (Kerrisk); deepen on purchase]
