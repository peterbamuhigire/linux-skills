# Process Priority, Resource Control, and systemd Targets

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

systemd on both supported families (Debian/Ubuntu and the RHEL family:
Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) runs every service inside
a **cgroup v2** control group. That gives you two complementary levers:

1. **Process priority** — `nice`/`renice` for CPU scheduling and `ionice`
   for disk I/O scheduling. Ad-hoc, per-process, applied from the shell.
2. **Service resource control** — the systemd unit directives `Nice=`,
   `CPUWeight=`, `IOWeight=`, `CPUQuota=`, `MemoryMax=`. Persistent,
   per-service, enforced by the kernel cgroup so a background service
   **cannot starve the host**.

And one orchestration concept:

3. **Targets** — the systemd replacement for SysV runlevels. They group
   units, define the boot state (`multi-user` vs `graphical`), and order
   the dependency graph (`WantedBy=`/`Requires=`/`After=`).

> Everything here works **identically** on both families — `systemctl`,
> cgroup v2, and the unit directives are part of systemd, not the distro.
> Only the example unit names differ (see the **Distro support** matrix in
> [`SKILL.md`](../SKILL.md)).

## Table of contents

1. Process priority: `nice` and `renice` (CPU)
2. Process priority: `ionice` (disk I/O)
3. cgroup v2 slices — why a background job can starve the host
4. Enforcing priority in systemd units (`Nice=`, `IOSchedulingClass=`)
5. cgroup resource control in units (`CPUWeight=`, `IOWeight=`, `CPUQuota=`, `MemoryMax=`)
6. Applying resource control at runtime (`systemctl set-property`)
7. Inspecting what a service is actually allowed (`systemd-cgtop`, `systemctl status`)
8. systemd targets: what they are and how they map to runlevels
9. The default target: `get-default` / `set-default`
10. `systemctl isolate` — switching state live
11. Dependency ordering: `WantedBy=`, `Requires=`, `Wants=`, `After=`/`Before=`
12. Worked example: a CPU- and I/O-limited background service
13. Sources

---

## 1. Process priority: `nice` and `renice` (CPU)

Every process gets a **niceness** value from `-20` (highest priority, most
CPU) to `+19` (lowest priority, "be nice to others"). The default is `0`.
A lower number is a *higher* scheduling priority. `top` shows the derived
priority column (`PR`) and the niceness (`NI`).

Use **`nice`** to *start* a process at an adjusted priority, and
**`renice`** to change a *running* process:

```bash
# Start an I/O- and CPU-heavy job at lower priority so it doesn't annoy users
nice -n 10 /usr/local/bin/backup.sh

# Lower the priority of an already-running process (PID 1234)
sudo renice -n 10 -p 1234

# Renice every process owned by a user, or in a process group
sudo renice -n 5 -u www-data
sudo renice -n 5 -g <pgid>
```

Rules that bite people:

- A **regular user can only *lower*** the priority (raise the nice number)
  of their own processes. **Only root can give a negative niceness**
  (raise priority). `renice -n -5 -p 1234` as a normal user fails.
- Move in increments of `5` and watch `top`; do not jump straight to the
  extremes.
- `nice` with no `-n` defaults to a +10 adjustment.

```bash
# From inside top: press 'r', enter the PID, then the new nice value.
# Press 'k' to send a signal to a PID.
```

---

## 2. Process priority: `ionice` (disk I/O)

CPU niceness does **not** govern disk I/O. A `nice -n 19` backup can still
saturate the disk queue and stall the database. `ionice` sets the **I/O
scheduling class** and, within a class, a priority `0`–`7` (0 = highest):

| Class | Number | Meaning |
|---|---|---|
| Realtime  | 1 | Gets disk access first, always. Dangerous — can starve everything else. Root only. |
| Best-effort | 2 | Default class. Priority 0 (highest) to 7 (lowest). Default priority is derived from the CPU nice value. |
| Idle      | 3 | Only gets disk I/O when nothing else wants it. Perfect for backups/reindex jobs. |

```bash
# Run a backup in the idle I/O class — it yields the disk to everyone else
ionice -c 3 /usr/local/bin/backup.sh

# Best-effort, lowest priority (7)
ionice -c 2 -n 7 /usr/local/bin/reindex.sh

# Change the I/O class of a running process (PID 1234)
sudo ionice -c 3 -p 1234

# Inspect current I/O class/priority of a process
ionice -p 1234
```

Combine both for a truly polite background job:

```bash
nice -n 19 ionice -c 3 /usr/local/bin/heavy-batch.sh
```

> Note: the `idle` and `realtime` classes only have a real effect under I/O
> schedulers that honor priorities (e.g. `bfq`/`mq-deadline`). On the
> `none` scheduler (common for NVMe) `ionice` classes may be ignored — check
> `cat /sys/block/<dev>/queue/scheduler`.

---

## 3. cgroup v2 slices — why a background job can starve the host

On modern Linux, cgroups allocate system resources. systemd organizes every
process into one of three top-level **slices**:

- **`system.slice`** — all systemd-managed services (nginx, mysql, your
  background jobs).
- **`user.slice`** — all interactive user sessions (including root logins).
- **`machine.slice`** — VMs and containers (optional).

The trap: **by default every slice has the same `CPUWeight`**, so under
contention all of `system.slice` collectively gets the *same* CPU share as
all of `user.slice` collectively — regardless of how many processes are in
each. One runaway service in `system.slice` can crowd out your other
services because they share that slice's budget. `nice`/`renice` only
re-orders processes *within* the same cgroup; it does **not** change how
much the slice gets relative to other slices. To control *that*, you need
cgroup resource control (sections 5–6).

```bash
systemd-cgls                         # tree of slices → scopes → services
systemctl status                     # shows the slice/cgroup tree at the bottom
cat /sys/fs/cgroup/cgroup.controllers   # confirm cgroup v2 (single unified hierarchy)
```

---

## 4. Enforcing priority in systemd units (`Nice=`, `IOSchedulingClass=`)

Rather than wrapping a service `ExecStart=` in `nice`/`ionice`, declare the
priority in the `[Service]` section. systemd applies it to the whole control
group:

```ini
[Service]
# CPU niceness, -20 (highest) .. 19 (lowest). Same scale as nice(1).
Nice=10

# I/O scheduling — same classes as ionice(1):
#   0 = none, 1 = realtime, 2 = best-effort, 3 = idle
IOSchedulingClass=idle
IOSchedulingPriority=7        # 0 (highest) .. 7 (lowest), within best-effort
```

`Nice=` and `IOSchedulingClass=` are the unit-file equivalents of `nice` and
`ionice`. They are the right tool for a **scheduled/oneshot** job (see the
timer example in [`timers-and-cron.md`](timers-and-cron.md)). For a
**long-running daemon** you usually want cgroup weights/quotas instead
(next section), because they hold under sustained contention.

---

## 5. cgroup resource control in units

These directives put a real, kernel-enforced ceiling/share on the service's
cgroup. A background service with these set **cannot starve the host**.

| Directive | Effect |
|---|---|
| `CPUWeight=`  | Relative CPU share under contention. `1`–`10000`, default `100`. A service at `50` gets half the CPU share of one at `100` when both want the CPU. Idle CPU is **not** wasted — this only kicks in under contention. |
| `CPUQuota=`   | Hard CPU ceiling as a percentage of **one** CPU. `CPUQuota=50%` = at most half a core. `CPUQuota=200%` = up to two full cores. Unlike `CPUWeight=`, this caps the service even when the box is idle. |
| `IOWeight=`   | Relative block-I/O share under contention. `1`–`10000`, default `100`. Needs the `bfq` I/O scheduler to take effect. |
| `IOReadBandwidthMax=` / `IOWriteBandwidthMax=` | Absolute I/O ceiling, e.g. `/var 50M`. |
| `MemoryMax=`  | Hard memory limit. Process is OOM-killed if it exceeds it. e.g. `MemoryMax=512M`. |
| `MemoryHigh=` | Soft limit — the kernel throttles and reclaims aggressively above it, but doesn't kill. Pair with a higher `MemoryMax=`. |
| `TasksMax=`   | Cap the number of tasks (PIDs/threads) — fork-bomb protection. |

```ini
[Service]
# A background indexer that must never dominate the host:
CPUWeight=20            # one-fifth the CPU share of a default service under load
CPUQuota=40%            # ...and never more than 0.4 of one core, even when idle
IOWeight=20             # low disk-I/O share under contention
MemoryHigh=256M         # throttle past 256M
MemoryMax=512M          # OOM-kill past 512M
TasksMax=64
```

> `CPUWeight=` replaces the older `CPUShares=`, and `IOWeight=` replaces
> `BlockIOWeight=` (and `MemoryMax=` replaces `MemoryLimit=`). The old names
> are cgroup-v1 spellings; on cgroup v2 use the new ones. See
> `systemd.resource-control(5)`.

After editing a unit:

```bash
sudo systemctl daemon-reload
sudo systemctl restart <service>
```

---

## 6. Applying resource control at runtime (`systemctl set-property`)

You don't have to edit a unit file and restart to apply a limit. `systemctl
set-property` writes a drop-in and applies it live:

```bash
# Give the whole system slice 8x the CPU share of the user slice
sudo systemctl set-property system.slice CPUWeight=800

# Cap a single running service to half a core, persistently
sudo systemctl set-property nginx.service CPUQuota=50%

# Apply only until the next reboot (no drop-in written)
sudo systemctl set-property --runtime mysql.service IOWeight=50
```

Without `--runtime`, systemd writes a drop-in under
`/etc/systemd/system/<unit>.d/50-*.conf` so the limit survives reboots.
Inspect with `systemctl cat <unit>`.

---

## 7. Inspecting what a service is actually allowed

```bash
# Live, top-like view of per-cgroup CPU/memory/IO usage
systemd-cgtop

# The effective value of one property on a unit
systemctl show nginx.service -p CPUWeight -p CPUQuota -p MemoryMax

# The cgroup tree + the service's own slice membership
systemctl status nginx.service        # CGroup: /system.slice/nginx.service
systemd-cgls /system.slice
```

`systemctl show -p <Property>` is the source of truth — it reports the
*effective* value after merging the vendor unit, drop-ins, and any
`set-property` overrides.

---

## 8. systemd targets: what they are and how they map to runlevels

A **target** is a named group of units that systemd brings up together. It
is the modern replacement for the SysV **runlevel**. A target unit
(`something.target`) by itself contains almost nothing — it just declares
what it `Requires=`, `Wants=`, and the ordering (`After=`). The actual
services are pulled in by their own `[Install]` `WantedBy=` (see section 11).

Targets that define a whole system state — these can be **isolated** (they
carry `AllowIsolate=yes`) and roughly map to the old runlevels:

| Target | Old runlevel | Meaning |
|---|---|---|
| `poweroff.target`   | 0 | Halt the system. |
| `rescue.target`     | 1 | Single-user; minimal services for repair. |
| `multi-user.target` | 3 | Full system, **no GUI** — the normal server default. |
| `graphical.target`  | 5 | Everything in multi-user **plus** a graphical login. |
| `reboot.target`     | 6 | Reboot. |
| `emergency.target`  | — | Even more minimal than rescue; only enough to fix a broken root filesystem. |

Other targets just bundle units and are pulled in by the big ones, e.g.
`timers.target` (all timers — see [`timers-and-cron.md`](timers-and-cron.md)),
`network-online.target`, `nfs.target`.

```bash
systemctl list-units --type=target          # active targets right now
systemctl list-units --type=target --all     # include inactive
systemctl cat multi-user.target              # see Requires=/After=/AllowIsolate
```

---

## 9. The default target: `get-default` / `set-default`

The **default target** is what the system boots into. On a headless server
that should almost always be `multi-user.target` — booting `graphical.target`
on a server wastes RAM on an X/Wayland stack nobody uses.

```bash
systemctl get-default                         # e.g. multi-user.target
sudo systemctl set-default multi-user.target  # boot without a GUI from now on
sudo systemctl set-default graphical.target   # boot into a desktop (needs the GUI pkgs)
```

`set-default` simply re-points the symlink
`/etc/systemd/system/default.target` at the chosen target. No reboot is
needed to *change* the setting; it takes effect on the next boot.

---

## 10. `systemctl isolate` — switching state live

`isolate` switches the **running** system to a target *now*, starting that
target's units and stopping everything not wanted by it. Only targets with
`AllowIsolate=yes` can be isolated.

```bash
sudo systemctl isolate rescue.target          # drop to single-user for repair
sudo systemctl isolate multi-user.target      # come back to full, headless operation
sudo systemctl isolate graphical.target       # bring up the GUI without rebooting
```

Difference from `start`: `systemctl start rescue.target` *adds* rescue's
units to the current state without stopping anything; `isolate` makes that
target the *exclusive* state, stopping units it doesn't want. For an actual
state change you want `isolate`, not `start`.

For emergencies you can also append `systemd.unit=rescue.target` (or
`emergency.target`) at the GRUB kernel line to boot straight into it.

---

## 11. Dependency ordering: `WantedBy=`, `Requires=`, `Wants=`, `After=`/`Before=`

Two **independent** axes — people constantly conflate them:

**Requirement** (does B get pulled in, and what if it fails?):

| Directive | Meaning |
|---|---|
| `Wants=B`    | Pull B in when this unit starts. If B fails, **this unit still starts**. Prefer this — it's the loose coupling. |
| `Requires=B` | Pull B in. If B fails to start or later stops, **this unit is stopped too**. Hard dependency. |
| `Requisite=B`| B must *already* be active, else this unit fails immediately (does not start B). |
| `Conflicts=B`| Starting this stops B, and vice-versa (how `isolate` tears down units). |

**Ordering** (what runs first — this is *not* a requirement):

| Directive | Meaning |
|---|---|
| `After=B`  | Do not start this unit until B has finished starting. |
| `Before=B` | The reverse. |

`Requires=` does **not** imply ordering. If you need B to be both present
*and* started first, you need **both** `Requires=B` and `After=B`.

**Enablement** — how a service attaches itself to a target:

```ini
[Install]
WantedBy=multi-user.target
```

When you `systemctl enable <service>`, systemd reads `[Install]` and creates
a symlink in `/etc/systemd/system/multi-user.target.wants/<service>` — i.e. it
adds the service to that target's "wants." That is exactly what makes the
service start at boot. `disable` removes the symlink.

```bash
ls /etc/systemd/system/multi-user.target.wants/   # what boots in multi-user
systemctl list-dependencies multi-user.target      # the full pulled-in tree
systemctl list-dependencies nginx.service          # what nginx needs / is needed by
```

Typical web-service ordering:

```ini
[Unit]
Description=My app
Wants=network-online.target
After=network-online.target postgresql.service
Requires=postgresql.service        # app is useless without the DB

[Install]
WantedBy=multi-user.target
```

---

## 12. Worked example: a CPU- and I/O-limited background service

Goal: a reindexing daemon that runs continuously but must never degrade the
web stack or the host, and only matters when the machine is in normal
multi-user operation.

Save at `/etc/systemd/system/reindexer.service`:

```ini
[Unit]
Description=Background search reindexer (resource-limited)
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User=reindex
ExecStart=/usr/local/bin/reindexer --daemon

# --- Priority (within its cgroup) ---
Nice=15
IOSchedulingClass=idle

# --- cgroup resource ceilings (host can never be starved) ---
CPUWeight=20            # low CPU share under contention
CPUQuota=50%            # hard cap: never more than half a core
IOWeight=20             # low disk share under contention
MemoryHigh=256M         # throttle above 256M
MemoryMax=512M          # OOM-kill above 512M
TasksMax=64

# --- Hardening (cheap, always worth it) ---
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/var/lib/reindexer

[Install]
WantedBy=multi-user.target
```

Activate and verify:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now reindexer.service

# Confirm the limits are effective
systemctl show reindexer.service -p CPUWeight -p CPUQuota -p MemoryMax -p Nice

# Watch it stay in its lane under load
systemd-cgtop
```

If you need to tighten it on a busy box without editing the file:

```bash
sudo systemctl set-property reindexer.service CPUQuota=25% MemoryMax=256M
```

---

## Sources

- `systemd.resource-control(5)` — `CPUWeight=`, `CPUQuota=`, `IOWeight=`,
  `MemoryMax=`/`MemoryHigh=`, `TasksMax=`; cgroup v2 semantics and the
  `set-property` runtime path.
- `systemd.exec(5)` — `Nice=`, `IOSchedulingClass=`, `IOSchedulingPriority=`.
- `systemd.unit(5)` / `systemd.target(5)` — `Wants=`, `Requires=`,
  `Requisite=`, `Conflicts=`, `After=`/`Before=`, `[Install] WantedBy=`,
  `AllowIsolate=`.
- `systemctl(1)` — `get-default`, `set-default`, `isolate`, `set-property`,
  `list-dependencies`, `list-units --type=target`.
- `nice(1)`, `renice(1)`, `ionice(1)` — niceness scale, I/O classes,
  root-only privilege escalation rules.
- **Red Hat RHCSA 10 Cert Guide (EX200), Sander van Vugt** — cgroup
  `system`/`user`/`machine` slices and equal-`CPUWeight` behavior;
  `systemctl set-property system.slice CPUWeight=800`; `nice`/`renice` value
  range (−20..19) and root-only negative niceness; targets table and
  runlevel mapping; `get-default`/`set-default`/`isolate`; the `wants`
  symlink mechanism behind `systemctl enable`.
- **Red Hat RHCSA 8 Cert Guide (EX200), Sander van Vugt** — `nice`/`renice`
  worked examples and the backup-vs-calculation priority scenarios.

> **[GROUNDING-GAP]** The RHCSA guides cover `nice`/`renice`, cgroup slices,
> and `systemctl set-property system.slice CPUWeight=` at a conceptual level,
> but do **not** document `ionice`, the per-unit `IOSchedulingClass=`,
> `IOWeight=`, `CPUQuota=`, `MemoryMax=`/`MemoryHigh=`, or `TasksMax=`
> directives. Those sections are grounded on the
> `systemd.resource-control(5)`, `systemd.exec(5)`, and `ionice(1)` man
> pages, plus the I/O-scheduler caveat (`bfq`/`none`) from the kernel block
> documentation. Verify exact behavior against the installed systemd version
> (`systemctl --version`) — older systemd may still use `CPUShares=`/
> `BlockIOWeight=` spellings.
