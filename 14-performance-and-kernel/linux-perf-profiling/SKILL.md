---
name: linux-perf-profiling
description: PERFORMANCE diagnosis — find the bottleneck before tuning, on both Linux families (Debian/Ubuntu and the RHEL family — Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). Read load average and `top`/`htop`, sample with `vmstat 1`, `iostat -x 1` (read `await`/`%util` for disk saturation), `mpstat -P ALL` (per-CPU), `pidstat` (per-process), and `sar` (sysstat historical). Classify the symptom as CPU-bound vs high I/O-wait vs memory pressure, then profile CPU on-CPU time with `perf` (`perf top`, `perf record -g` + `perf report`, `perf stat`). Covers sysstat/perf install and `kernel.perf_event_paranoid`. For tuning the kernel after you measure, hand off to linux-sysctl-tuning.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Linux Performance Profiling

`[GROUNDING-GAP: perf/iostat/sar profiling — grounded on man pages + kernel perf
docs; deepen with Systems Performance 2e and BPF Performance Tools (Brendan
Gregg).]`

## Distro support

One-family-pair skill: the tools below behave **identically** on Debian/Ubuntu
and the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). The
`/proc`-backed tools (`uptime`, `top`, `vmstat`, `free`, `ps`) ship in `procps`
(Debian) / `procps-ng` (RHEL) and are usually preinstalled. The sysstat tools
(`iostat`, `mpstat`, `pidstat`, `sar`) come from the **`sysstat`** package on
both families. `perf` is the only tool whose package name differs.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Load + run queue | `uptime`, `top`, `htop` | `uptime`, `top`, `htop` |
| Virtual-memory sampling | `vmstat 1` | `vmstat 1` |
| Per-device I/O | `iostat -x 1` | `iostat -x 1` |
| Per-CPU breakdown | `mpstat -P ALL 1` | `mpstat -P ALL 1` |
| Per-process | `pidstat 1` | `pidstat 1` |
| Historical (collected) | `sar` (sysstat) | `sar` (sysstat) |
| sysstat install | `apt install sysstat` | `dnf install sysstat` |
| sysstat collector | `sysstat.service` + cron / `sysstat-collect.timer` | `sysstat.service` + `sysstat-collect.timer` |
| `perf` install | `apt install linux-perf` **or** `linux-tools-$(uname -r)` + `linux-tools-common` | `dnf install perf` |
| perf access gate | `kernel.perf_event_paranoid` (sysctl) | same |

`htop` is in the default repos on both (`apt install htop` / `dnf install
htop`); on minimal RHEL it may need EPEL on older releases.

## Use when

- A host is "slow" and you must locate the bottleneck before changing anything.
- Deciding whether the limit is CPU, disk I/O, or memory before tuning.
- You need a CPU profile (which functions burn cycles) via `perf`.
- You want historical context (`sar`) for an incident that already happened.

## Do not use when

- You already know the bottleneck and only need to apply kernel tunables; use
  `linux-sysctl-tuning`.
- The question is per-service CPU/memory share or limits; use
  `linux-service-priority` (cgroups).
- You are tracing application logic, not system resources (use app-level APM).

## Required inputs

- The symptom (latency, throughput drop, OOM, high load) and when it occurs.
- Whether you can install packages (`sysstat`, `perf`) on the host.
- Whether the issue is live (sample now) or past (need `sar` history).

## Methodology (USE)

Brendan Gregg's **USE** method — for each resource, check **U**tilization,
**S**aturation, **E**rrors — keeps profiling systematic instead of guessing:

| Resource | Utilization | Saturation | Errors |
|---|---|---|---|
| CPU | `mpstat -P ALL` (%idle) | run queue `r` in `vmstat`, load avg | — |
| Memory | `free -h` used vs avail | swap in/out `si`/`so` in `vmstat` | OOM in `dmesg` |
| Disk | `iostat -x` `%util` | `iostat -x` `await`, queue `aqu-sz` | I/O errors in `dmesg` |

Work top-down: read load average, then split CPU vs I/O-wait vs memory with one
`vmstat 1` sample, then drill into the saturated resource with the specific
tool. **Measure first; tune second** (then hand off to `linux-sysctl-tuning`).

## Workflow

1. **Triage:** `uptime` (load vs core count), then `vmstat 1` for a few lines.
2. **Classify:** high `wa` → disk; high `r` with low idle → CPU; high `si`/`so`
   or low available memory → memory pressure (see decision table below).
3. **Drill:** disk → `iostat -x 1`; CPU → `mpstat -P ALL 1` + `pidstat 1`;
   memory → `free -h`, `vmstat`, `dmesg | grep -i oom`.
4. **Profile CPU** (if CPU-bound): `perf top`, then `perf record -g` +
   `perf report` to see the hot stacks.
5. **Conclude:** name the bottleneck and the evidence; hand off to a tuning
   skill rather than tuning blind here.

## Quality standards

- Sample over a window (`vmstat 1`, several lines) — never trust one instant.
- Ignore the first `iostat`/`mpstat` line: it is averages since boot, not now.
- Pair every claim with the field that proves it (e.g. "disk-bound: `%util` 98,
  `await` 40 ms").

## Anti-patterns

- Tuning sysctl/storage before measuring the actual bottleneck.
- Reading the since-boot first sample as the current state.
- Treating high load average as automatically CPU — on Linux load includes
  uninterruptible (D-state, usually I/O) tasks.
- Running `perf record` system-wide for minutes on a busy box without bounding
  it (`-F` frequency, a fixed duration) — the perf.data file balloons.

## Outputs

- The classified bottleneck (CPU / I/O-wait / memory) and the metrics proving it.
- For CPU cases, the top symbols/stacks from `perf report`.
- A concrete next step (which tuning skill, which subsystem).

## Triage: classify the bottleneck

Take one `vmstat 1` window and read three columns:

```bash
vmstat 1 5
# procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
#  r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
```

| Symptom in `vmstat` | Likely bottleneck | Drill with |
|---|---|---|
| `wa` high (e.g. ≥ 20%), `id` low | **I/O-wait** (disk) | `iostat -x 1`, `pidstat -d 1` |
| `r` > #CPUs, `us`+`sy` high, `id`~0 | **CPU-bound** | `mpstat -P ALL 1`, `pidstat 1`, `perf top` |
| `si`/`so` non-zero, `free` tiny, `cache` shrinking | **Memory pressure / swapping** | `free -h`, `dmesg | grep -i oom` |

`#CPUs` = `nproc`. Load average above `nproc` is normal only if the extra tasks
are runnable (CPU) — if they are in D-state (`ps -eo stat`), it is I/O.

## Live tools

```bash
uptime                       # 1/5/15-min load avg; compare to `nproc`
top                          # press '1' for per-CPU, 'P'/'M' sort by CPU/MEM
htop                         # nicer top: per-core bars, tree view, F6 sort
vmstat 1                     # virtual-mem/CPU/IO sampling (ignore line 1)
free -h                      # memory: look at 'available', not 'free'
```

### Disk I/O — `iostat -x`

```bash
iostat -x 1                  # extended per-device stats (ignore first sample)
```

Read these fields per device:

- **`%util`** — fraction of time the device had I/O in flight. Near 100% means
  the device is saturated (caveat: for SSD/NVMe with parallel queues, `%util`
  can hit 100% while the device still has headroom — corroborate with `await`).
- **`await`** — average ms per I/O (queue + service time). Rising `await` under
  load is the clearest saturation signal; spinning disks ~5–15 ms healthy,
  tens-to-hundreds ms = backed up.
- **`r/s` `w/s`** and **`rkB/s` `wkB/s`** — IOPS and throughput, to see whether
  the load is random (high IOPS) or sequential (high kB/s).
- **`aqu-sz`** (avg queue length) — sustained > 1 means requests are queuing.

A disk bottleneck is **high `%util` AND high `await`** together. Then find the
culprit process with `pidstat -d 1`.

### Per-CPU and per-process — `mpstat` / `pidstat`

```bash
mpstat -P ALL 1              # per-core %usr/%sys/%iowait/%idle — spot a hot core
pidstat 1                    # per-process %CPU each interval
pidstat -d 1                 # per-process disk read/write KB/s
pidstat -r 1                 # per-process memory faults / RSS
```

One core pinned at 100% while others idle = a single-threaded hot path (`mpstat`
exposes this; `top`'s aggregate hides it).

### Historical — `sar` (sysstat)

`sar` reads the data the `sysstat` collector records on a schedule, so you can
look **back** at an incident:

```bash
sar                          # today's CPU history (default)
sar -u                       # CPU; sar -r memory; sar -b I/O; sar -n DEV network
sar -d -p                    # per-device disk (pretty device names)
sar -f /var/log/sysstat/saYYMMDD   # a specific past day's file
```

Enable collection once: install `sysstat`, then enable the collector
(`systemctl enable --now sysstat` and, on most distros,
`sysstat-collect.timer`). Without it, `sar` has no history.

## CPU profiling with `perf`

`perf` samples the CPU and attributes time to functions — it answers *which code
is hot*, which `top`/`mpstat` cannot.

```bash
# Install: Debian -> linux-perf OR linux-tools-$(uname -r) + linux-tools-common
#          RHEL   -> dnf install perf

perf top                              # live, top symbols by CPU (like top, per-fn)
perf stat -- <cmd>                    # counters for one command: IPC, cache, ctx-sw
perf stat -a sleep 5                  # system-wide counters for 5s

# Sampled profile with call graphs:
perf record -g -- <cmd>               # profile one command (-g = call stacks)
perf record -g -p <PID> -- sleep 30   # attach to a running PID for 30s
perf record -g -a -- sleep 30         # whole system for 30s (bound the duration!)
perf report                           # interactive browser of perf.data
perf report --stdio | head -40        # non-interactive top stacks
```

Read `perf stat` for cheap insight first: **IPC** (instructions/cycle) below ~1
suggests stalls (memory-bound); high **context-switches** suggests scheduling
contention; high **cache-misses** points at memory layout.

### `kernel.perf_event_paranoid`

The kernel gates non-root perf access via this sysctl. Values:

| Value | Allows (non-root) |
|---|---|
| `3` | nothing (some hardened Debian/Ubuntu defaults) |
| `2` | user-space measurements only (common default) |
| `1` | + kernel profiling |
| `0` | + raw tracepoints / per-CPU |
| `-1` | no restrictions |

```bash
sysctl kernel.perf_event_paranoid          # check current
sudo sysctl -w kernel.perf_event_paranoid=1   # transient; for kernel symbols
```

Lowering it system-wide weakens isolation — prefer running `perf` as root for a
one-off, or persist a relaxed value only on a trusted profiling host. See
`linux-sysctl-tuning` for the drop-in persistence pattern.

### Flame graphs

Turn a `perf record` into a flame graph (visual stack census) with Brendan
Gregg's FlameGraph scripts — see
[`references/profiling-tools.md`](references/profiling-tools.md) for the pipe.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-perf-profiling
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-perf-snapshot | scripts/sk-perf-snapshot.sh | yes | Read-only quick-profile snapshot: captures a short window of load/uptime, `free -h`, `vmstat`, `iostat -x` (await/%util), `mpstat -P ALL`, `pidstat`, top processes by %CPU and %MEM, and (unless `--no-perf`) a 1s `perf stat`, then prints a one-line verdict (CPU-bound vs I/O-wait vs memory pressure). Degrades gracefully if sysstat/perf are absent. Never mutates. Both families. |

## References

- [`references/profiling-tools.md`](references/profiling-tools.md)
