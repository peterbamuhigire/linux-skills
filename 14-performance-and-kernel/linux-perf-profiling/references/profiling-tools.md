# Profiling tools reference

Deeper command reference for `linux-perf-profiling`. Tools behave identically on
Debian/Ubuntu and the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma,
Oracle); only package names differ (`linux-perf`/`linux-tools-$(uname -r)` vs
`perf`; `sysstat` on both).

`[GROUNDING-GAP: perf/iostat/sar profiling — grounded on man pages + kernel perf
docs; deepen with Systems Performance 2e and BPF Performance Tools (Brendan
Gregg).]`

---

## sysstat package

`iostat`, `mpstat`, `pidstat`, and `sar` all ship in **`sysstat`**:

```bash
sudo apt install sysstat      # Debian/Ubuntu
sudo dnf install sysstat      # RHEL family
```

For `sar` history you must enable the collector (it records to
`/var/log/sysstat/` or `/var/log/sa/`):

```bash
sudo systemctl enable --now sysstat
# Modern sysstat also uses timers:
sudo systemctl enable --now sysstat-collect.timer sysstat-summary.timer 2>/dev/null || true
# Debian: collection toggle in /etc/default/sysstat (ENABLED="true")
```

**First-sample rule (applies to iostat/mpstat/sar interval output):** the first
interval reported is the average *since boot*, not the current state. Always
discard it and read subsequent samples.

---

## `vmstat`

```bash
vmstat 1            # 1-second samples
vmstat -w 1         # wide columns (large numbers don't truncate)
vmstat -s           # one-shot event/memory totals
```

Key columns:

| Group | Field | Meaning |
|---|---|---|
| procs | `r` | runnable + running tasks (run queue). > `nproc` = CPU saturation |
| procs | `b` | tasks in uninterruptible sleep (usually blocked on I/O) |
| swap | `si` / `so` | KB/s swapped **in** / **out** — non-zero = memory pressure |
| io | `bi` / `bo` | blocks/s read from / written to block devices |
| system | `in` / `cs` | interrupts and context-switches per second |
| cpu | `us`/`sy`/`id`/`wa`/`st` | user / system / idle / **I/O-wait** / stolen (VM) |

`wa` is the share of idle time spent waiting on outstanding I/O — high `wa` with
low `id` is the canonical disk-bound signature. `st` (steal) high on a VM means
the hypervisor is starving you of CPU.

---

## `iostat -x` field meanings

```bash
iostat -x 1            # extended, 1s interval (ignore first sample)
iostat -xz 1           # -z hides idle devices
iostat -dx -p sda 1    # one device, with partitions
iostat -m 1            # MB/s instead of kB/s
```

Per-device extended fields (names vary slightly by sysstat version):

| Field | Meaning | Saturation reading |
|---|---|---|
| `r/s`, `w/s` | read / write requests completed per second (IOPS) | — |
| `rkB/s`, `wkB/s` | KB read / written per second (throughput) | — |
| `rrqm/s`, `wrqm/s` | requests merged per second (adjacent I/O coalesced) | high merge = sequential |
| `r_await`, `w_await` | avg ms per read / write (queue + service) | rising = backing up |
| `await` | avg ms per I/O (all) | tens–hundreds ms = saturated |
| `aqu-sz` (old `avgqu-sz`) | avg outstanding requests | sustained > 1 = queuing |
| `rareq-sz`/`wareq-sz` | avg request size (KB) | small+high IOPS = random |
| `%util` | % wall-time with ≥1 request in flight | ~100% = busy (see caveat) |

**`%util` caveat:** it measures *time the device was busy*, not how busy. On
devices that service requests in parallel (SSD, NVMe, RAID, SAN LUNs) `%util`
can reach 100% while the device still has throughput headroom. Trust `await` and
`aqu-sz` for those; `%util` is most reliable for a single spinning disk.

**Bottleneck signature:** high `%util` **and** rising `await` **and** `aqu-sz`
climbing together. Then attribute it with `pidstat -d 1`.

---

## `mpstat`

```bash
mpstat 1             # all-CPU aggregate, 1s
mpstat -P ALL 1      # per-core breakdown
```

Columns: `%usr %nice %sys %iowait %irq %soft %steal %guest %idle`. A single core
near 0% idle while others idle reveals a single-threaded hot path that aggregate
`top` hides. High `%soft` (softirq) on one core often means network interrupt
load not spread across cores (check IRQ affinity / RPS).

---

## `pidstat`

Per-process counters over an interval (better than `ps` snapshots):

```bash
pidstat 1            # %CPU per process each second
pidstat -u 1         # CPU (explicit)
pidstat -d 1         # disk read/write KB/s per process (needs CAP / root for all)
pidstat -r 1         # memory: minflt/s, majflt/s, RSS — majflt/s = page-ins (pressure)
pidstat -w 1         # context switches per process
pidstat -t 1         # per-thread
pidstat -p <PID> 1   # one process
```

`majflt/s` (major faults) being non-zero for a process means it is faulting
pages back from disk/swap — a per-process memory-pressure signal.

---

## `sar` (historical)

`sar` replays what the collector recorded, so you can investigate after the
fact:

```bash
sar -u                 # CPU utilization (today)
sar -r                 # memory utilization
sar -S                 # swap usage
sar -b                 # I/O transfer rate (tps, read/write)
sar -d -p              # per-block-device activity (pretty names)
sar -n DEV             # per-NIC network throughput
sar -q                 # run-queue length and load averages
sar -W                 # swapping (pages in/out)
sar -f /var/log/sysstat/saDD   # a specific day's archive (Debian: /var/log/sysstat)
sar -s 09:00:00 -e 10:00:00    # restrict to a time window
```

RHEL stores archives in `/var/log/sa/`; Debian/Ubuntu in `/var/log/sysstat/`.

---

## `perf` workflow

Install: Debian `linux-perf` **or** `linux-tools-$(uname -r)` +
`linux-tools-common`; RHEL `dnf install perf`.

```bash
# 1. Live overview
perf top                          # top symbols by CPU; -g for call graphs
perf top -p <PID>                 # one process

# 2. Counter summary (cheap, no symbols needed)
perf stat -- <cmd>                # IPC, cache-misses, branch-misses, ctx-switches
perf stat -a sleep 5              # system-wide for 5s
perf stat -e cycles,instructions,cache-misses -- <cmd>

# 3. Sampled profile with stacks
perf record -g -- <cmd>           # one command (-g = call stacks)
perf record -g -p <PID> -- sleep 30
perf record -F 99 -g -a -- sleep 30   # 99 Hz, whole system, BOUNDED to 30s
perf report                       # interactive TUI over perf.data
perf report --stdio --sort overhead,symbol | head -40
perf script                       # raw samples (feed to flame-graph tooling)
```

Interpreting `perf stat`:

- **IPC (insn per cycle)** < ~1.0 → the CPU is stalling (often memory-bound);
  > 2 is good for most workloads.
- **cache-misses** high relative to references → poor data locality.
- **context-switches / cpu-migrations** high → scheduling contention or too many
  runnable threads.

Bound `perf record -a` with a duration and a sane frequency (`-F 99`) so
`perf.data` and overhead stay manageable on a busy host.

### `kernel.perf_event_paranoid`

Gates non-root access:

| Value | Non-root may |
|---|---|
| `3` | nothing |
| `2` | user-space only (common default) |
| `1` | + kernel profiling |
| `0` | + raw tracepoints, per-CPU events |
| `-1` | unrestricted |

```bash
sysctl kernel.perf_event_paranoid
sudo sysctl -w kernel.perf_event_paranoid=1     # transient
```

Prefer running `perf` as root for one-off profiling rather than relaxing this
host-wide. To persist on a dedicated profiling box, use a `/etc/sysctl.d/`
drop-in (see `linux-sysctl-tuning`). Kernel symbol resolution also needs
`kernel.kptr_restrict=0` (security-relevant — revert after).

---

## Flame graphs

A flame graph turns sampled stacks into a visual census (x = sample count, y =
stack depth) so the widest boxes are where CPU time goes.

```bash
git clone https://github.com/brendangregg/FlameGraph
perf record -F 99 -g -- <cmd>           # or -p PID / -a, bounded
perf script | ./FlameGraph/stackcollapse-perf.pl | ./FlameGraph/flamegraph.pl > out.svg
```

Open `out.svg` in a browser; click a frame to zoom. For mixed kernel/user
stacks ensure frame pointers or DWARF (`perf record --call-graph dwarf`) and
debug symbols are available.

---

## See also

- `linux-sysctl-tuning` — apply kernel tunables **after** you have measured.
- `linux-service-priority` — cgroup CPU/IO/memory limits for a single service.
- Brendan Gregg, *Systems Performance, 2nd ed.* and *BPF Performance Tools* —
  authoritative depth on the USE method, `iostat`/`sar` internals, and `perf`.
