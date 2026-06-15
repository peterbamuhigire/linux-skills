---
name: linux-inmemory-stores
description: Operate Redis and Memcached in-memory data stores across both major Linux families — install (redis-server / memcached on Debian/Ubuntu; redis / memcached on the RHEL family: Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle), secure the network surface (bind address, Redis protected-mode, requirepass / ACL, Memcached -l listen and SASL), set eviction policy (maxmemory, maxmemory-policy allkeys-lru / volatile-lru / noeviction), and configure Redis persistence (RDB save snapshots vs AOF appendonly — Memcached has none). systemd management and a hard warning against exposing either daemon to an untrusted network.
license: MIT
metadata:
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

## Use when

- Installing and locking down a fresh Redis or Memcached instance.
- Choosing and applying an eviction policy for a cache workload.
- Configuring Redis persistence (RDB snapshots, AOF, or both) or deciding none.
- Diagnosing memory pressure, eviction, client limits, or an exposed daemon.

## Do not use when

- The task is a relational engine (MySQL/MariaDB, PostgreSQL); use
  `linux-mysql-mariadb` (or the PostgreSQL skill).
- The task is storing or injecting the auth password itself; use `linux-secrets`
  to manage the `requirepass`/SASL secret, then return here to apply it.
- The task is host firewalling of the exposed port; use `linux-firewall-ssl`.

## Required inputs

- Which store (Redis, Memcached, or both) and the intended role (cache vs
  durable store — only Redis can be durable).
- Memory budget (`maxmemory` for Redis, `-m` for Memcached) and whether eviction
  or hard-refusal (`noeviction`) is the correct behavior on a full cache.
- Whether any non-localhost client needs access, and from which trusted network.

## Workflow

1. Install the package for the family; start and enable the unit.
2. Confirm the bind address before exposing anything — both default to localhost.
3. Set authentication (Redis `requirepass`/ACL; Memcached SASL) before binding to
   any non-loopback address. Pull the secret via `linux-secrets`.
4. Set the memory ceiling and eviction policy to match the workload.
5. For Redis, decide persistence: RDB, AOF, both, or none (pure cache).
6. Verify: `redis-cli INFO` / `memcached-tool ... stats`; confirm the listen
   socket and that auth is required.

## Quality standards

- Never expose Redis or Memcached to an untrusted network. Bind to localhost or a
  private interface, require authentication, and firewall the port.
- Set `maxmemory` explicitly on Redis caches — an unbounded Redis will consume all
  RAM and be OOM-killed.
- Keep the secret out of the world-readable config where possible; reference
  `linux-secrets` for password handling.

## Anti-patterns

- `bind 0.0.0.0` (or removing the `bind` line) with `protected-mode no` and no
  `requirepass` — this is the classic remote-takeover footgun.
- Running Redis as a persistent store with persistence disabled (no RDB, no AOF)
  and assuming data survives a restart — it does not.
- Treating Memcached as durable: it has **no persistence** — every restart starts
  empty.

## Outputs

- The bind address, auth method, and firewall posture chosen.
- The eviction policy and memory ceiling set, with the rationale.
- For Redis, the persistence mode (RDB/AOF/both/none) and where files live.

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
