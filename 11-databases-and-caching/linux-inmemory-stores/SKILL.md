---
name: linux-inmemory-stores
description: Use when installing, securing, sizing, or diagnosing Redis or Memcached on Debian/Ubuntu or RHEL-family hosts; covers bind/auth, eviction, and Redis persistence. Use linux-mysql-mariadb for relational databases and linux-firewall-ssl for host policy.
license: MIT
metadata:
  portable: true
  compatible_with: [claude-code, codex]
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Redis & Memcached (in-memory stores)

## Distro support

Two-family skill. Both stores ship in the base repositories of every supported
distro; the split that matters is the **package name** (and on RHEL the optional
`redis6`/`redis7` Application Stream module) and the **Memcached defaults file**
(`/etc/memcached.conf` on Debian vs `/etc/sysconfig/memcached` on RHEL). The body
below uses the Debian/Ubuntu paths; full RHEL detail is in
[`references/redis-reference.md`](references/redis-reference.md) and
[`references/memcached-reference.md`](references/memcached-reference.md).

| Concept | Debian/Ubuntu | RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) |
|---|---|---|
| Install Redis | `apt install redis-server` | `dnf install redis` |
| Install Memcached | `apt install memcached` | `dnf install memcached` |
| Redis config | `/etc/redis/redis.conf` | `/etc/redis/redis.conf` (or `/etc/redis.conf`) |
| Redis service | `redis-server` | `redis` |
| Memcached defaults | `/etc/memcached.conf` (one flag per line) | `/etc/sysconfig/memcached` (`OPTIONS=`, `CACHESIZE=`, `PORT=`) |
| Memcached service | `memcached` | `memcached` |
| Redis CLI | `redis-cli` | `redis-cli` |
| Memcached SASL pkg | `libsasl2-modules` (+ `sasldb`) | `cyrus-sasl`, `cyrus-sasl-plain` |
| Logs | `journalctl -u redis-server` / `-u memcached` | `journalctl -u redis` / `-u memcached` |

Both daemons bind to localhost by default on a fresh package install — keep it
that way unless you have deliberately firewalled and authenticated the service.
Use the `svc_name` / `pkg_install` helpers from `common.sh` in `sk-*` scripts so
one script runs on both families; see
[`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

> [GROUNDING-GAP: Redis/Memcached — these stores are NOT in the corpus; grounded
> on official redis.io and memcached.org / GitHub wiki documentation; deepen with
> the Redis docs (redis.io/docs) and the memcached(1) man page and wiki.]

<!-- dual-compat-start -->
## Use When

- Installing and locking down a fresh Redis or Memcached instance.
- Choosing and applying an eviction policy for a cache workload.
- Configuring Redis persistence (RDB snapshots, AOF, or both) or deciding none.
- Diagnosing memory pressure, eviction, client limits, or an exposed daemon.

## Do Not Use When

- The task is a relational engine (MySQL/MariaDB, PostgreSQL); use
  `linux-mysql-mariadb` (or the PostgreSQL skill).
- The task is storing or injecting the auth password itself; use `linux-secrets`
  to manage the `requirepass`/SASL secret, then return here to apply it.
- The task is host firewalling of the exposed port; use `linux-firewall-ssl`.

## Required Inputs

| Artefact | Required? | Source | If absent |
|---|---|---|---|
| Store, version, distro family, and role (cache or durable Redis) | yes | Operator and host inventory | Stop before package or config changes; report the missing facts. |
| Memory budget and full-cache behaviour | yes | Capacity plan or measured workload | Inspect available memory read-only; propose measurements, but do not apply a ceiling or eviction policy. |
| Client networks and authentication requirement | yes | Application topology and security policy | Keep loopback binding; do not expose the service. |
| Persistence and recovery objective | Redis only | Service owner | Treat Redis as a cache and warn that restart data loss is expected. |

## Capability Contract

Inspection requires read access to service state, sockets, and configuration. Installation, configuration edits, firewall changes, restarts, and secret placement require explicit host-mutation authority and least-privilege elevation. Never print authentication material.

## Degraded Mode

Without host access, return a family-specific change plan and verification commands. Without workload measurements, do not invent a memory ceiling. If authentication or socket exposure cannot be checked, mark the service posture `not assessed`, never safe.

## Decision Rules

| Choice | Action | Failure or risk avoided |
|---|---|---|
| Memcached versus Redis | Use Memcached only for disposable cache data; use Redis when data structures or optional persistence are required. | False durability assumptions. |
| Local versus remote clients | Retain loopback unless trusted client CIDRs, authentication, and firewall controls are all defined. | Unauthenticated remote takeover. |
| Redis eviction | Use `allkeys-lru` for a pure cache, `volatile-lru` for TTL-scoped eviction, or `noeviction` where failed writes are safer than data loss. | Silent eviction of durable keys. |
| Redis persistence | Select RDB, AOF, both, or none from the recovery objective and test restart recovery. | Unrecoverable data loss. |

## Workflow

1. Confirm the input contract and identify the distro family, store, role, authority, and rollback path; stop if exposure or durability requirements are unknown.
2. Inspect installed package, active unit, socket, memory use, and current configuration before changing anything.
3. Decide the store, memory ceiling, eviction, persistence, and access model with the decision table.
4. With explicit mutation authority, install the family package and start the correct unit.
5. Set authentication (Redis ACL/password or Memcached SASL) before binding to
   any non-loopback address. Pull the secret via `linux-secrets`.
6. Apply memory, eviction, and Redis persistence decisions, validate syntax, then restart or reload only as required.
7. Verify with `redis-cli INFO` or `memcached-tool ... stats`, socket inspection, an unauthenticated rejection test, and a persistence recovery test when applicable. On failure, restore the saved config, restart the prior unit state, and re-check the socket.

## Quality Standards

- Never expose Redis or Memcached to an untrusted network. Bind to localhost or a
  private interface, require authentication, and firewall the port.
- Set `maxmemory` explicitly on Redis caches — an unbounded Redis will consume all
  RAM and be OOM-killed.
- Keep the secret out of the world-readable config where possible; reference
  `linux-secrets` for password handling.
- Record unit, socket, ceiling, authentication result, and persistence result without exposing secrets.

## Anti-Patterns

- Exposing a cache before authentication. Fix: keep loopback binding until auth and firewall checks pass.
- Choosing eviction from a generic recipe. Fix: inspect workload role, TTLs, and memory statistics first.
- Leaving Redis memory unbounded. Fix: set a measured ceiling with OS and persistence headroom.
- Claiming Redis durability without recovery. Fix: restart-test the selected RDB/AOF mode.
- Putting credentials in commands or evidence. Fix: use approved secret retrieval and redact output.

- Exposing `0.0.0.0` with protected mode disabled and no auth. Correction: bind narrowly, authenticate, and firewall before remote access.
- Running Redis without `maxmemory`. Correction: set a measured ceiling that leaves headroom for the OS and fork operations.
- Treating Memcached as durable. Correction: document it as disposable and rebuild cache contents after restart.
- Enabling Redis persistence without a recovery test. Correction: restore or restart-test RDB/AOF on a non-production instance.
- Placing passwords in command history or evidence. Correction: retrieve secrets through the approved channel and redact outputs.
- Changing eviction policy without checking key TTL patterns. Correction: inspect keyspace statistics and choose policy from workload semantics.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Store configuration record | Service owner | Names bind address, auth method, ceiling, eviction, and Redis persistence without secrets. |
| Verification result | Operator | Unit is healthy, expected socket is present, unauthenticated access is rejected, and authorised stats are readable. |
| Recovery evidence | Service owner | Redis persistence test passes, or cache-only data loss is explicitly accepted. |

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| Store evidence pack | Contains redacted config, version, socket, authentication, memory/eviction, and recovery results; unavailable checks are marked. |

Capture redacted config excerpts, package/unit versions, socket output, authentication rejection, memory/eviction statistics, and recovery-test result. Unavailable checks remain `not assessed`.

## Worked Example

A 2 GiB Redis cache with disposable keys and private application clients receives a measured `maxmemory` below host capacity and `allkeys-lru`; ACL authentication is configured before the private bind. Acceptance requires the expected private socket, rejected unauthenticated `PING`, authorised `INFO memory`, and a documented decision that persistence is disabled.

## Install

```bash
# Debian/Ubuntu
sudo apt install redis-server memcached
sudo systemctl enable --now redis-server memcached

# RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle)
sudo dnf install redis memcached
sudo systemctl enable --now redis memcached
```

> **Security warning.** Both daemons bind to `127.0.0.1` by default. Do **not**
> remove that without (a) authentication enabled, (b) a host firewall
> (`linux-firewall-ssl`) restricting the port to a trusted source, and (c) a
> deliberate decision to expose the service. An open Redis on the internet is
> trivially compromised (write to disk via `CONFIG SET dir`, SSH key injection,
> module load). Memcached on a public UDP port is a known DDoS amplification
> vector — disable UDP (`-U 0`) unless you need it.

## Security & network surface

```bash
# Redis — see the listen socket and whether auth is set:
redis-cli CONFIG GET bind
redis-cli CONFIG GET protected-mode
redis-cli CONFIG GET requirepass        # empty string = NO password set

# Set a password at runtime (then persist with CONFIG REWRITE):
redis-cli CONFIG SET requirepass 'use-linux-secrets-for-this'
redis-cli -a 'use-linux-secrets-for-this' CONFIG REWRITE
```

Redis: keep `protected-mode yes` (the default), bind only to the interfaces you
need, and set `requirepass` or — better — define an ACL user. Memcached: bind
with `-l <addr>`, disable UDP with `-U 0`, and enable SASL (`-S`) if it must be
reachable off-host. Store the password with **`linux-secrets`**, never inline in
a committed config. Deep dives:
[`references/redis-reference.md`](references/redis-reference.md),
[`references/memcached-reference.md`](references/memcached-reference.md).

## Eviction (memory policy)

A cache must have a memory ceiling and a policy for what happens when it is hit.

```ini
# /etc/redis/redis.conf
maxmemory 512mb
# allkeys-lru   : evict least-recently-used across all keys (typical cache)
# volatile-lru  : evict LRU only among keys with a TTL (mixed cache+durable)
# noeviction    : refuse writes when full (durable store — never lose data)
maxmemory-policy allkeys-lru
```

```bash
# Memcached caps memory at -m megabytes and evicts LRU within a slab class
# automatically — there is no policy knob; -m IS the ceiling.
#   /etc/memcached.conf -> -m 256
```

Apply Redis live, then make it persist across restarts:
```bash
redis-cli CONFIG SET maxmemory 512mb
redis-cli CONFIG SET maxmemory-policy allkeys-lru
redis-cli CONFIG REWRITE
```

Rationale, every policy, and `maxmemory-samples`:
[`references/redis-reference.md`](references/redis-reference.md).

## Persistence (Redis only)

Memcached has **no persistence** — note this and plan for a cold cache on every
restart. Redis offers two mechanisms, usable together:

```ini
# /etc/redis/redis.conf

# RDB — point-in-time binary snapshots. Compact, fast restart, can lose the
# writes since the last snapshot. "save <seconds> <changes>":
save 900 1
save 300 10
save 60 10000
dbfilename dump.rdb
dir /var/lib/redis

# AOF — appends every write op; replayed on restart. Better durability, larger
# file, slower restart. fsync policy: everysec (default) balances safety/speed.
appendonly yes
appendfsync everysec
```

```bash
redis-cli BGSAVE                 # trigger an RDB snapshot now (background)
redis-cli BGREWRITEAOF           # compact the AOF
redis-cli INFO persistence       # rdb_last_save_time, aof_enabled, last status
```

RDB vs AOF tradeoffs, combined mode, and recovery:
[`references/redis-reference.md`](references/redis-reference.md).

## systemd management

```bash
sudo systemctl status redis-server      # RHEL: redis
sudo systemctl restart memcached
journalctl -u redis-server --no-pager | tail -30
```

<!-- dual-compat-end -->

## References

- [`references/redis-reference.md`](references/redis-reference.md)
- [`references/memcached-reference.md`](references/memcached-reference.md)
- Official upstream: redis.io/docs, memcached.org and the memcached(1) man page.
- Password handling: `linux-secrets`. Port firewalling: `linux-firewall-ssl`.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-inmemory-stores
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-redis-status | scripts/sk-redis-status.sh | yes | Read-only Redis status: `INFO` memory (used / maxmemory / policy), persistence (RDB last-save, AOF state), and client/connection counts; flags a hard FAIL if Redis is bound to `0.0.0.0` with no `requirepass`. Both families. PASS/WARN/FAIL summary. |
