# Monitoring Commands Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

A full reference for local, live performance monitoring on Ubuntu/Debian
servers. Every command in this file is either pre-installed or available
from the stock apt repositories. The emphasis is not "here is a command"
— it's "here is what the numbers mean and what to watch for." Use it as
the companion to `SKILL.md` for the cases where the quick health check
isn't enough.

## Table of contents

1. Load average and the 0.7-per-core rule
2. CPU utilisation: `top`, `htop`, `atop`, `btop`
3. Per-CPU breakdown: `mpstat`
4. Memory: `free`, `/proc/meminfo`, swap
5. Process memory: `ps`, `pmap`, `smem`
6. `vmstat` — the whole-system snapshot
7. Disk I/O: `iostat`, `iotop`, `pidstat -d`
8. Disk space and inodes: `df`, `du`, `ncdu`
9. Block devices and filesystems: `lsblk`, `lsof`, `findmnt`
10. Network: `ss`, `ip -s link`, `/proc/net/dev`
11. Network traffic: `nload`, `iftop`, `bmon`
12. Historical metrics with `sar` (sysstat)
13. Sensors and hardware: `sensors`, `lscpu`, `dmidecode`
14. `/proc` — the kernel interface
15. Open files and file descriptors
16. Sources

---

## 1. Load average and the 0.7-per-core rule

Load average is the average number of processes in the run queue or
waiting for uninterruptible I/O, over 1, 5, and 15-minute windows.

```bash
uptime
#  14:32:01 up 42 days,  3:17,  2 users,  load average: 0.52, 0.74, 0.81
```

- First number = now.
- Second = 5 minutes ago.
- Third = 15 minutes ago.

Interpretation (for a machine with `N` CPU cores):

| Load       | Meaning                                                   |
|------------|-----------------------------------------------------------|
| < 0.7 × N  | Healthy. Room to grow.                                    |
| ≈ N        | Saturated. Every core is busy. Requests queue a little.   |
| > N        | Over-committed. Things are slowing down.                  |
| > 2 × N    | Severe contention. Investigate now.                       |

Get the core count:

```bash
nproc                      # count of usable cores
lscpu | grep -E "^CPU\(s\):|Thread|Core|Socket"
```

Watch the **trend**, not a single number. A load of 3.0 on a 4-core box
is only interesting if it's rising. Compare the 1/5/15-minute values:

- 1m > 5m > 15m → load is rising (bad if already saturated).
- 1m < 5m < 15m → load is falling (the storm is passing).

Who is logged in and what they are doing:

```bash
who
w
```

`w` also prints the load averages, plus each session's TTY, idle time,
and the currently-running command. Useful on shared boxes.

---

## 2. CPU utilisation: top / htop / atop / btop

### top (always available)

```bash
top                          # interactive
top -bn1 | head -20          # one snapshot, no-pager (scripts, cron)
top -bn1 -o %CPU | head -20  # sorted by CPU
top -bn1 -o %MEM | head -20  # sorted by memory
```

Header columns worth reading:

- `%Cpu(s): us sy ni id wa hi si st`
  - `us` — userspace CPU.
  - `sy` — kernel CPU.
  - `ni` — niced userspace CPU.
  - `id` — idle.
  - `wa` — waiting for I/O. Sustained > 20% = disk bottleneck.
  - `hi` — hardware interrupts.
  - `si` — software interrupts.
  - `st` — stolen by a hypervisor (cloud VM starvation).

Process columns: `PID`, `USER`, `PR`, `NI`, `VIRT`, `RES`, `SHR`,
`S` (state: R/S/D/Z), `%CPU`, `%MEM`, `TIME+`, `COMMAND`. Watch for:

- State `D` (uninterruptible sleep) — process stuck in a kernel call,
  usually I/O. Multiple `D` processes ≈ I/O storm.
- State `Z` (zombie) — child that the parent hasn't reaped. Large zombie
  counts point to a buggy supervisor.

### htop (`apt install htop`)

Prettier, interactive, per-core bars at the top. Keys:

- `F2` or `S` — setup.
- `F5` or `t` — tree view.
- `F6` or `<` — change sort column.
- `P` — sort by CPU. `M` — sort by memory. `T` — sort by time.
- `F9` or `k` — kill a process (signal menu).
- `/` — filter.

### atop (`apt install atop`)

Records system activity every 10 minutes by default (`atop.service` logs
to `/var/log/atop/`). Replay historical periods:

```bash
atop -r /var/log/atop/atop_$(date +%Y%m%d)
# Press t / T to step forward/back, m for memory, d for disk, n for net
```

This is the closest thing stock Ubuntu gives you to a "flight recorder"
— if you weren't watching at 03:00 when things went wrong, atop has.

### btop (`apt install btop`)

The modern, eye-candy replacement for htop. Nothing functionally new,
but it includes GPU and network traffic panes out of the box.

### Quick one-liners

```bash
ps aux --sort=-%cpu | head -10              # top 10 by CPU
ps aux --sort=-%mem | head -10              # top 10 by memory
ps -eo pid,ppid,user,cmd,%mem,%cpu --sort=-%mem | head
```

---

## 3. Per-CPU breakdown: `mpstat`

`mpstat` is part of the `sysstat` package (`apt install sysstat`). It
breaks CPU usage down per-core, so you can catch a single pegged core
that the averaged `top` header hides.

```bash
mpstat                       # one snapshot
mpstat -P ALL                # per-core snapshot
mpstat -P ALL 1 5            # per-core, every 1s, 5 samples
```

Watch for:

- One core at 100% `%usr` while others are idle → single-threaded
  bottleneck (one PHP-FPM worker eating a request, a runaway cron).
- High `%soft` (software interrupts) on `CPU0` only → a network driver
  that hasn't been RSS/RPS-balanced.
- Non-zero `%steal` on cloud VMs → the hypervisor is oversubscribed;
  your noisy neighbour is taking cycles.

---

## 4. Memory: `free`, `/proc/meminfo`, swap

```bash
free -h
#               total        used        free      shared  buff/cache   available
# Mem:           7.7Gi       3.2Gi       312Mi       146Mi       4.2Gi       4.0Gi
# Swap:          2.0Gi       120Mi       1.9Gi
```

Column meanings (`-h` gives human units):

- `total` — installed RAM.
- `used` — in use by userspace + kernel (excludes cache).
- `free` — completely unused. Low `free` is **not** a problem.
- `shared` — `tmpfs` and shared memory segments.
- `buff/cache` — kernel file-system cache. Reclaimable on demand.
- **`available` — the important number.** Kernel's estimate of memory
  available for a new process without swapping. If this drops under
  10% of `total`, you're under memory pressure.

Rule of thumb:

| `available` as % of `total` | State                                              |
|-----------------------------|----------------------------------------------------|
| > 20%                       | Healthy.                                           |
| 10–20%                      | Keep an eye on it.                                 |
| < 10%                       | Memory pressure. Swap use incoming. Investigate.   |
| < 5%                        | OOM kill imminent.                                 |

### Swap reality check

```bash
free -h
swapon --show
cat /proc/swaps
```

Swap use is only bad if it's **active** — kernel will page out long-idle
pages as an optimisation, even on a healthy box. Confirm with `si`/`so`
in vmstat (section 6): if both stay 0, the swap that's used is cold and
fine.

### /proc/meminfo deep dive

```bash
cat /proc/meminfo | grep -E \
  "MemTotal|MemFree|MemAvailable|Buffers|Cached|SReclaimable|SwapCached|SwapTotal|SwapFree|Dirty|Writeback|AnonPages|Mapped|Shmem|Slab|KernelStack|PageTables"
```

Things worth scanning:

- `Dirty:` — pages modified but not written back. Spikes under heavy
  write load; the kernel flushes on `vm.dirty_background_ratio`.
- `Writeback:` — pages actively being written. Persistent high values =
  disk throughput ceiling.
- `Slab:` — kernel data structures. Large `Slab` with `SReclaimable`
  that won't shrink = a filesystem that's caching too many inodes.
- `AnonPages:` — anonymous (non-file-backed) pages. This is your
  processes' actual RAM.

---

## 5. Process memory: `ps`, `pmap`, `smem`

```bash
ps aux --sort=-%mem | head -10
ps -eo pid,rss,vsz,comm --sort=-rss | head
```

Columns:

- `VSZ` — virtual size. Almost never meaningful on its own.
- `RSS` — resident set size. Real RAM used, in kilobytes.
- `%MEM` — RSS / total RAM.

### Accurate memory accounting with `smem` (`apt install smem`)

```bash
smem -tk                     # totals, KB units
smem -rk -s rss | head       # sort by RSS
smem -rk -s pss | head       # sort by PSS (fair shared-memory split)
```

`PSS` is the right number when you want to know "how much memory is
this process *really* costing me, including its fair share of shared
libraries."

### Per-process memory map

```bash
sudo pmap -x $(pgrep -f nginx | head -1)
```

Shows every memory region (heap, stack, mapped libs, mmap'd files) with
size and permissions. Useful when an RSS number looks wrong and you
want to know what's in it.

---

## 6. `vmstat` — the whole-system snapshot

```bash
vmstat 1 10
# procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
#  r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
#  1  0      0 312440 128456 4200100    0    0    12    28  201  450  3  1 95  1  0
```

Columns worth interpreting:

- `r` — run queue length. > `nproc` = CPU saturation.
- `b` — processes in uninterruptible sleep. > 0 sustained = I/O wait.
- `si`/`so` — swap in/out. **Both should be 0 at steady state.** Non-zero
  = real swap activity, real memory pressure.
- `bi`/`bo` — blocks in/out from block devices. Spikes during backups.
- `in` — interrupts per second.
- `cs` — context switches per second. Huge `cs` with low useful work =
  lock contention or too many threads.
- `wa` — I/O wait %. Sustained > 20% = disk bottleneck.
- `st` — stolen by hypervisor. > 5% on a cloud VM = throttling.

The first row of `vmstat` is an average since boot — **ignore it**.
Look at the subsequent rows.

---

## 7. Disk I/O: `iostat`, `iotop`, `pidstat -d`

### iostat (sysstat package)

```bash
iostat -xz 1 5               # extended, skip zero-activity devices
```

Columns worth interpreting for each device:

- `r/s`, `w/s` — read/write requests per second.
- `rkB/s`, `wkB/s` — read/write throughput.
- `rareq-sz`, `wareq-sz` — average request size. Large = sequential;
  small = random.
- `aqu-sz` — average queue length. > 1 = sustained queue depth.
- `await` — average time in ms from queue to completion. The headline
  latency number. > 20ms = slow response; > 50ms = painful.
- `r_await`, `w_await` — split read/write await. A one-sided number
  (writes slow, reads fine, or vice versa) points to a specific workload.
- `svctm` — (deprecated in modern iostat) service time. Ignore.
- `%util` — percentage of wall clock the device was busy. > 80%
  sustained = saturated.

Example read of a bad output:

```
Device   r/s   w/s   rkB/s   wkB/s  rareq-sz  wareq-sz  aqu-sz  await  %util
sda     2.0  450.0    16.0  28000.0      8.0      62.0    12.3  27.5  98.5
```

98.5% utilisation, writes at 28 MB/s with 450 ops and 27ms average await
— the disk is pegged on writes, most likely a backup or a runaway log
writer. Confirm with `iotop`.

### iotop (`apt install iotop`)

```bash
sudo iotop -bod 5            # batch, only processes with I/O, 5s interval
sudo iotop -oPa              # interactive, per-process, accumulated
```

The `-o` flag hides processes that have done zero I/O — cuts out noise.

### pidstat -d — per-process I/O

```bash
pidstat -d 1 5               # every 1s, 5 samples, per-process disk I/O
pidstat -dl 1 5              # with long command lines
```

Columns: `kB_rd/s`, `kB_wr/s`, `kB_ccwr/s` (cancelled writes — pages
dirtied and then dropped), `iodelay`.

---

## 8. Disk space and inodes: `df`, `du`, `ncdu`

```bash
df -h                              # human-readable, every mounted fs
df -h -x tmpfs -x devtmpfs         # skip ramdisks
df -i                              # inode usage instead of bytes
df -h /var                         # just the fs that contains /var
```

Inodes can exhaust independently of space. If `df -h` says you have
10 GB free but you still can't create files, run `df -i`. A tiny cache
directory with millions of 1 KB files will wreck you.

```bash
du -sh /var/log/* /var/www/* 2>/dev/null | sort -rh | head -20
du -sh --max-depth=1 / 2>/dev/null | sort -rh
```

Interactive tree explorer:

```bash
sudo apt install ncdu
sudo ncdu /var                     # navigate with arrow keys, d deletes
```

Find the biggest files:

```bash
sudo find / -xdev -type f -size +500M -printf '%s %p\n' 2>/dev/null | \
    sort -rn | head -20
```

`-xdev` keeps `find` on one filesystem — essential so you don't wander
into `/proc`, `/sys`, or a bind-mounted backup.

Full cleanup strategy: see `linux-disk-storage/references/cleanup-patterns.md`.

---

## 9. Block devices and filesystems

```bash
lsblk                              # tree of block devices
lsblk -f                           # with fs type, UUID, mount
lsblk -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,MOUNTPOINT,UUID,FSTYPE
findmnt                            # mount tree, more readable than mount
findmnt /var                       # what's mounted at /var
findmnt -S /dev/sda1               # where is this device mounted
mount | column -t                  # classic view
```

`lsblk -f` is the fastest way to answer "what is mounted where and what
filesystem is on it."

---

## 10. Network: `ss`, `ip -s link`, `/proc/net/dev`

`ss` replaces `netstat`. It reads from `/proc/net/tcp` directly and is
much faster on boxes with lots of sockets.

```bash
ss -tulnp                          # TCP + UDP + listening + numeric + programs
ss -tnp                            # TCP, established only, with processes
ss -s                              # socket summary by protocol and state
ss -tan state established          # only established TCP
ss -tan state time-wait | wc -l    # how many TIME_WAITs
ss -tn 'sport = :443'              # only port 443
ss -tn 'dst 10.0.0.5'              # only connections to a host
```

Connection state counts (canonical one-liner):

```bash
ss -tan | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn
```

Watch for:

- Thousands of `TIME_WAIT` — normal on busy web servers; not a problem
  unless you run out of ephemeral ports.
- Growing `CLOSE_WAIT` — the **local** side hasn't closed. Indicates an
  application bug (forgot to close sockets).
- Many `SYN-RECV` — possible SYN flood.

Replaces `netstat`:

```bash
netstat -tulnp                     # legacy equivalent of `ss -tulnp`
```

### ip -s link

```bash
ip -s link                         # per-interface RX/TX packets, drops, errors
ip -s link show eth0               # one interface
ip -brief addr                     # quick IP assignment view
```

Look at `dropped` and `errors`. Non-zero dropped counters climbing over
time = NIC misconfigured, buffer overrun, or driver problem.

### /proc/net/dev

```bash
cat /proc/net/dev
```

The raw counters `ip -s link` prints.

---

## 11. Network traffic tools

### nload (`apt install nload`)

Per-interface live bandwidth chart. Use it when you want to see "is my
traffic spike coming from `eth0` or `eth1`?"

### iftop (`apt install iftop`)

Live per-connection bandwidth: who is talking to whom, and how fast.

```bash
sudo iftop -i eth0 -nNP            # numeric, with ports
```

Keys: `t` cycles display mode, `s`/`d` toggle source/destination.

### bmon (`apt install bmon`)

Pretty real-time interface stats with history graphs.

### tcpdump — the universal packet capture

```bash
sudo tcpdump -i eth0 -nn port 443 -c 100
sudo tcpdump -i eth0 -nn 'host 10.0.0.5 and port 22'
```

Use when you need to prove a packet did or did not arrive.

---

## 12. Historical metrics with `sar` (sysstat)

`sar` (from the `sysstat` package) records system activity to
`/var/log/sysstat/` so you can retroactively ask "what was the CPU doing
at 3 AM last Tuesday?"

### Enable collection

```bash
sudo apt install sysstat
sudo sed -i 's/ENABLED="false"/ENABLED="true"/' /etc/default/sysstat
sudo systemctl enable --now sysstat
```

On Ubuntu 22.04+ collection is also driven by `sysstat.timer` (runs
every 10 minutes). Confirm:

```bash
systemctl list-timers | grep sysstat
ls -l /var/log/sysstat/
```

### Read history

```bash
sar -u                             # CPU, today, every 10min
sar -u 1 5                         # live CPU, 1s interval, 5 samples
sar -r                             # memory history
sar -b                             # block I/O history
sar -d                             # per-device I/O history
sar -n DEV                         # per-interface network history
sar -q                             # load average, run queue, process count
sar -S                             # swap utilisation
sar -W                             # pages swapped
sar -f /var/log/sysstat/sa10       # read a specific day (sa10 = day 10)
sar -s 02:00:00 -e 04:00:00        # restrict to a time window
```

Combine: `sar -u -s 14:00 -e 15:00` — CPU utilisation between 2pm and
3pm today. Quick post-mortem workflow.

---

## 13. Sensors and hardware

```bash
sudo apt install lm-sensors
sudo sensors-detect --auto         # scan and write /etc/modules-load.d/
sensors                            # current readings
sensors -f                         # Fahrenheit
```

Shows CPU package temperature, per-core temperature, fan RPM, voltages,
if the motherboard exposes them. Thermal throttling under load is a
real cause of "half my CPU is missing" mysteries on cheap hosts.

### CPU topology and features

```bash
lscpu                              # architecture, cores, MHz, flags
lscpu -e                           # per-CPU topology table
nproc --all                        # every CPU including offline
cat /proc/cpuinfo                  # the kernel's full view
```

### Hardware inventory

```bash
sudo dmidecode -t system           # manufacturer, model, serial
sudo dmidecode -t memory           # DIMM slots, sizes, speeds, ECC?
sudo dmidecode -t processor
lspci                              # PCI devices
lsusb                              # USB devices
```

---

## 14. `/proc` — the kernel interface

Virtually every kernel state is exposed under `/proc`. Worth memorising:

| Path                       | Contents                                                          |
|----------------------------|-------------------------------------------------------------------|
| `/proc/loadavg`            | `1m 5m 15m running/total last_pid` — what `uptime` reads.         |
| `/proc/meminfo`            | Every memory counter.                                             |
| `/proc/stat`               | Counter-of-everything since boot (CPU ticks, context switches).   |
| `/proc/uptime`             | Seconds since boot, idle time.                                    |
| `/proc/cpuinfo`            | Per-CPU model, flags, MHz.                                        |
| `/proc/version`            | Kernel version, compiler, build date.                             |
| `/proc/mounts`             | Authoritative mount list.                                         |
| `/proc/partitions`         | Block devices.                                                    |
| `/proc/net/dev`            | Per-interface counters.                                           |
| `/proc/net/tcp`            | All TCP sockets.                                                  |
| `/proc/net/udp`            | All UDP sockets.                                                  |
| `/proc/sys/`               | Live `sysctl` values.                                             |
| `/proc/<pid>/status`       | Per-process human-readable status.                                |
| `/proc/<pid>/fd/`          | Symlinks to every open file the process holds.                    |
| `/proc/<pid>/limits`       | Per-process resource limits (the effective `ulimit`).             |
| `/proc/<pid>/cmdline`      | The full argv, NUL-separated.                                     |
| `/proc/<pid>/environ`      | The process environment at launch.                                |
| `/proc/<pid>/io`           | Bytes read/written for the process.                               |
| `/proc/<pid>/smaps`        | Detailed memory mapping.                                          |

Examples:

```bash
cat /proc/loadavg
cat /proc/meminfo | head -5
ls /proc/$(pgrep -f nginx | head -1)/fd | wc -l   # open FD count for nginx
cat /proc/$(pgrep -f mysqld | head -1)/limits
```

---

## 15. Open files and file descriptors

```bash
lsof -i :443                       # who owns port 443?
lsof -i -n -P | head               # all TCP/UDP sockets, numeric
lsof -p $(pgrep -f mysqld | head -1) | head
lsof +D /var/log                   # everything with an open file under /var/log
lsof -u www-data | head
lsof | grep deleted | head         # deleted-but-held files (disk-full hero)
```

`lsof | grep deleted` is the classic "I truncated that log file with
`rm` and disk isn't freed up" rescue tool. The disk space only comes
back when the process that held the file descriptor closes it or
restarts.

FD usage per process:

```bash
ls /proc/<pid>/fd | wc -l
cat /proc/<pid>/limits | grep "open files"
```

System-wide FD usage:

```bash
cat /proc/sys/fs/file-nr
#  18464   0   9223372036854775807
#  allocated  unused  max
```

---

## Sources

- **Ubuntu Server Guide (Focal 20.04)**, Canonical (2020) — baseline
  Ubuntu monitoring defaults and sysstat integration.
- **Mastering Ubuntu**, Ghada Atef (2023) — monitoring tools overview;
  `top`, `htop`, `vmstat`, `iostat` chapter.
- **Linux System Administration for the 2020s** — modern monitoring
  patterns; sar, `ss`, `journalctl` as the primary tooling.
- **Wicked Cool Shell Scripts**, Dave Taylor & Brandon Perry — disk
  usage reporting and log digest patterns.
- `proc(5)`, `ss(8)`, `ip(8)`, `iostat(1)`, `vmstat(8)`, `sar(1)`,
  `lsof(8)`, `top(1)`, `htop(1)` man pages.
- Real-world operational experience on production Ubuntu 20.04 / 22.04
  / 24.04 servers.
