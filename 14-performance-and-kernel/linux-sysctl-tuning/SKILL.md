---
name: linux-sysctl-tuning
description: Use when measured Linux performance evidence justifies persistent network, queue, writeback, swap, or congestion-control sysctl changes on Debian/Ubuntu or RHEL-family hosts. Profile first; use linux-server-hardening for security sysctls.
license: MIT
metadata:
  portable: true
  compatible_with: [claude-code, codex]
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Sysctl Performance Tuning

## Distro support

One-family-pair skill: the `sysctl` interface, the `/etc/sysctl.d/` drop-in
directory, and `sysctl --system` are **identical** on Debian/Ubuntu and the
RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). The kernel
exposes the same `net.*` and `vm.*` keys on both. Only the package that ships a
given module differs.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Show one key | `sysctl net.core.somaxconn` | `sysctl net.core.somaxconn` |
| Show all keys | `sysctl -a` | `sysctl -a` |
| Set live (transient) | `sysctl -w vm.swappiness=10` | `sysctl -w vm.swappiness=10` |
| Persist | `/etc/sysctl.d/60-perf.conf` | `/etc/sysctl.d/60-perf.conf` |
| Reload all drop-ins | `sudo sysctl --system` | `sudo sysctl --system` |
| BBR module | `tcp_bbr` (in-tree, modprobe) | `tcp_bbr` (in-tree, modprobe) |
| Available cc list | `sysctl net.ipv4.tcp_available_congestion_control` | same |

`[GROUNDING-GAP: BBR/swappiness/TCP-buffer perf tuning — thin/absent in the
RHCSA grounding corpus; authored from kernel networking docs (Documentation/
networking, Documentation/admin-guide/sysctl) and tcp(7)/sysctl(8) man pages.
Deepen with Systems Performance 2e (Brendan Gregg).]`

<!-- dual-compat-start -->
## Use When

- Raising socket buffers / TCP window for high-throughput (10GbE+) transfers.
- Scaling a server to many concurrent connections (`somaxconn`, syn backlog).
- Enabling **BBR** congestion control with the `fq` qdisc.
- Tuning memory writeback / swap behaviour (`swappiness`, `dirty_ratio`).

## Do Not Use When

- The goal is SECURITY hardening (rp_filter, tcp_syncookies, kptr_restrict,
  redirects). That sysctl lives in `linux-server-hardening`
  (`references/sysctl-reference.md`) — cross-reference it, do not duplicate it.
- The bottleneck is per-service CPU/memory share; use `linux-service-priority`
  (cgroup limits) instead.
- You are diagnosing, not tuning; profile first with `linux-perf-profiling`.

## Required Inputs

| Artefact | Required? | Source | If absent |
|---|---|---|---|
| Measured bottleneck, workload/SLO, baseline, and candidate key rationale | yes | `linux-perf-profiling` evidence | Stop; do not tune from a generic recipe. |
| Kernel/version, current/effective values, config precedence, and feature availability | yes | Host inspection | Produce read-only discovery only. |
| Load test, window, rollback threshold, and authority | mutation | Change plan | Do not apply persistent or live values. |

- The workload class (throughput-bound transfer, connection-heavy server, or
  balanced general server).
- The NIC speed and expected concurrent-connection count.
- Whether a maintenance window applies (most keys are live, but verify).

## Capability Contract

Reading sysctls and drop-ins is read-only. Live writes, drop-in edits, module loading, load generation, and rollback require explicit authority. Security sysctls route to `linux-server-hardening`.

## Degraded Mode

Without representative load testing, return candidate keys and an experiment design only. If a key/algorithm is unavailable, do not force it. If rollback cannot be observed, do not apply the change.

## Decision Rules

| Choice | Action | Failure or risk avoided |
|---|---|---|
| Tune or retain | Change only a key linked to measured saturation and a testable hypothesis. | Cargo-cult tuning. |
| Live or persistent | Test the narrow live delta, then persist only a verified winner in one owned drop-in. | Boot-time regression. |
| BBR | Select only when available and pair with supported pacing qdisc after workload comparison. | Unsupported congestion setup. |
| Keep or rollback | Keep only if target metric improves without crossing guardrails; otherwise restore previous values. | Hidden latency/memory regression. |

## Workflow

1. **Measure first** — profile with `linux-perf-profiling` so you tune the real
   bottleneck, not a guess.
2. Show the current live value of each candidate key (`sysctl <key>`).
3. Write the delta to a drop-in in `/etc/sysctl.d/` (never edit
   `/etc/sysctl.conf` or vendor files in `/usr/lib/sysctl.d/`).
4. Apply with `sudo sysctl --system` and re-read the keys to confirm.
5. Load-test, then keep or roll back by deleting the one drop-in.

6. Stop when target improvement is absent or a guardrail regresses; recover by removing the owned drop-in, restoring recorded live values, and rerunning the baseline test.

## Quality Standards

- One owned drop-in file, high number prefix (e.g. `60-`/`99-`) so it wins.
- Set only keys you can justify against a measured bottleneck.
- Confirm BBR is available before selecting it (`tcp_available_congestion_control`).

## Anti-Patterns

- Copying a tuning blob. Fix: link every key to measured saturation and a hypothesis.
- Editing vendor/global config. Fix: use one owned drop-in with documented precedence.
- Claiming improvement without comparable load. Fix: repeat baseline and candidate under identical workload.
- Forcing unavailable BBR or qdisc support. Fix: inspect kernel features before selection.
- Keeping a regressing change. Fix: enforce guardrails and restore prior effective values.

- Copy-pasting a giant "ultimate sysctl" blob without measuring.
- Editing `/etc/sysctl.conf` directly (use a drop-in — easy diff/rollback).
- Setting `vm.swappiness=0` (can trigger OOM under pressure; 10 is the safe low).
- Mixing security and performance keys in one file (split ownership).
- Claiming improvement without a comparable load test. Correction: repeat baseline and candidate runs under the same workload.
- Ignoring config precedence. Correction: inspect effective values and every supplying drop-in before choosing the filename.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Tuning hypothesis | Performance owner | Links each key to measured evidence, target metric, guardrail, and rollback threshold. |
| Owned drop-in/change record | Operator | Contains only approved deltas plus before/after effective values and rollback. |
| Experiment result | Service owner | Comparable test shows improvement and guardrails, or records successful rollback. |

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| Tuning experiment evidence | Contains kernel/config provenance, before/after values, comparable load metrics, guardrails, and rollback result. |

Capture kernel, feature availability, config provenance, before/after keys, load-test parameters and metrics, errors, guardrails, and rollback result.

## Worked Example

After profiling shows a connection-accept queue bottleneck, record current `somaxconn`, application backlog, and saturation, test one bounded increase under the same load, then persist only if latency improves without memory or error regression.

- The drop-in file written and the keys it changed.
- Before/after values for each tuned key.
- The load-test result that justified (or reverted) the change.

## sysctl basics

```bash
sysctl net.core.somaxconn                 # read one key
sysctl -a | grep tcp_congestion           # search
sudo sysctl -w vm.swappiness=10           # transient (lost on reboot)

# Persist: a drop-in is read at boot and by `sysctl --system`.
# Files are read in lexical order across /usr/lib, /run, /etc — last wins.
sudo tee /etc/sysctl.d/60-perf.conf >/dev/null <<'EOF'
net.core.somaxconn = 65535
vm.swappiness = 10
EOF
sudo sysctl --system                      # apply ALL drop-ins
```

## High-throughput networking

```bash
# Socket buffer ceilings (bytes) — needed for large bandwidth-delay products.
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
# Per-socket TCP autotuning: min default max
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# BBR congestion control — pair it with the fq qdisc (BBR's pacing needs fq).
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

```bash
# Verify BBR is usable BEFORE setting it:
sysctl net.ipv4.tcp_available_congestion_control     # must list 'bbr'
sudo modprobe tcp_bbr                                 # load if absent
```

## Connection scaling

```bash
net.core.somaxconn = 65535          # accept-queue depth (also raise app backlog!)
net.ipv4.tcp_max_syn_backlog = 8192 # half-open (SYN_RECV) queue
net.core.netdev_max_backlog = 16384 # per-CPU packet ingress queue
net.ipv4.ip_local_port_range = 1024 65535   # ephemeral ports for outbound
net.ipv4.tcp_tw_reuse = 1           # reuse TIME_WAIT sockets for new outbound
```

> `somaxconn` only caps the kernel queue; the application's `listen()` backlog
> must be raised too (e.g. nginx `backlog=`, the app's listen() argument).

## Memory behaviour

```bash
vm.swappiness = 10            # 0..200; lower = avoid swap, keep page cache (NOT 0)
vm.dirty_ratio = 20          # % RAM dirty before a writing process blocks
vm.dirty_background_ratio = 5 # % RAM dirty before kernel starts async flush
vm.overcommit_memory = 0     # 0=heuristic, 1=always, 2=strict (with overcommit_ratio)
```

## Cross-reference: security sysctl

SECURITY-focused `net.*`/`kernel.*` tunables (`rp_filter`, `tcp_syncookies`,
`kptr_restrict`, `accept_redirects`, core-dump hygiene) are owned by the
**`linux-server-hardening`** skill — see its
`references/sysctl-reference.md`. Keep security keys in that skill's drop-in
and performance keys in this one; do not move or duplicate either set.

## Optional fast path (when sk-* scripts are installed)

| Task | Fast-path script |
|---|---|
| Show live vs profile delta (read-only) | `sk-sysctl-tune --profile throughput` |
| Write a profile drop-in + `sysctl --system` | `sudo sk-sysctl-tune --profile web --apply` |
| Preview an apply without writing | `sudo sk-sysctl-tune --profile web --apply --dry-run` |

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-sysctl-tuning
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-sysctl-tune | scripts/sk-sysctl-tune.sh | no | Show live vs target for a PERFORMANCE profile (throughput/web/balanced), read-only by default; with --apply writes a `/etc/sysctl.d/` drop-in and runs `sysctl --system` after confirmation. Dry-run-aware; verifies BBR availability. Both families. |

<!-- dual-compat-end -->

## References

- [`references/sysctl-tuning-reference.md`](references/sysctl-tuning-reference.md)
