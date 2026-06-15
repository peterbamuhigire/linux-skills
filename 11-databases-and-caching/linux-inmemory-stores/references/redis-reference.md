# Redis: redis.conf deep dive (both families)

> [GROUNDING-GAP: Redis/Memcached — grounded on official redis.io docs; deepen
> with Redis docs (redis.io/docs/management/config, .../persistence,
> .../security/acl). Not present in the corpus; author conservatively.]

Config file: `/etc/redis/redis.conf` (Debian/Ubuntu and most RHEL builds; some
RHEL builds use `/etc/redis.conf`). Service unit is `redis-server` on
Debian/Ubuntu and `redis` on the RHEL family. After editing the file, restart;
for live changes use `CONFIG SET` then `CONFIG REWRITE` to persist them back.

## Memory & eviction

```ini
maxmemory 512mb              # 0 (default) = no limit -> Redis can exhaust RAM
maxmemory-policy allkeys-lru # what to do when maxmemory is reached
maxmemory-samples 5          # eviction is approximate LRU/LFU; samples N keys
```

Policies:

| Policy | Behavior | Use for |
|---|---|---|
| `noeviction` | Return errors on writes when full (reads/deletes still work) | Durable store — never silently drop data |
| `allkeys-lru` | Evict least-recently-used across all keys | General-purpose cache |
| `allkeys-lfu` | Evict least-frequently-used across all keys | Cache with hot/cold skew |
| `volatile-lru` | Evict LRU only among keys that have a TTL set | Mixed cache + persistent keys |
| `volatile-lfu` | Evict LFU only among keys with a TTL | Mixed, frequency-biased |
| `volatile-ttl` | Evict keys with a TTL, shortest TTL first | TTL-driven expiry |
| `allkeys-random` / `volatile-random` | Evict random key(s) | Rarely the right answer |

`volatile-*` policies evict nothing if no key has a TTL — Redis then behaves like
`noeviction` and write errors begin. Set TTLs, or use an `allkeys-*` policy.

## Persistence: RDB vs AOF

| | RDB (snapshot) | AOF (append-only file) |
|---|---|---|
| What | Periodic binary point-in-time dump (`dump.rdb`) | Log of every write op, replayed on start |
| Durability | Loses writes since last snapshot | `everysec`: lose ≤1s; `always`: per-write fsync |
| Restart speed | Fast (load one compact file) | Slower (replay the log) |
| File size | Small | Larger; grows until rewritten |
| Best for | Backups, fast restart, tolerant of small loss | Lower data-loss window |

```ini
# RDB
save 900 1                   # snapshot if >=1 key changed in 900s
save 300 10
save 60 10000
dbfilename dump.rdb
dir /var/lib/redis           # where dump.rdb AND appendonly files live

# AOF
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec         # everysec | always | no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
```

You can enable **both**: AOF is the source of truth on restart, RDB gives fast
backups. For a pure cache, disable both (`save ""`, `appendonly no`) and accept a
cold start. Recovery: stop Redis, place `dump.rdb` / `appendonly.aof` in `dir`,
start. `redis-check-rdb` / `redis-check-aof` validate (and `--fix` AOF) a file.

```bash
redis-cli BGSAVE             # snapshot now, in background (non-blocking)
redis-cli BGREWRITEAOF       # compact the AOF
redis-cli INFO persistence   # rdb_last_bgsave_status, aof_enabled, aof_last_*
```

## Authentication: requirepass and ACL

Setting a password is the minimum; ACL users are the modern, granular form.

```ini
# Legacy single password (becomes the 'default' user's password):
requirepass <strong-secret>

# ACL: define named users with command/key scopes. Prefer this.
user default off                                   # disable the unauth default
user app on >+<strong-secret> ~app:* +@read +@write -@dangerous
```

Manage the secret with **`linux-secrets`** — do not commit it into a
world-readable `redis.conf`. Tighten file perms (`chmod 640`, owner `redis`).

```bash
redis-cli ACL LIST                     # current users
redis-cli ACL WHOAMI
redis-cli ACL SETUSER app on '>secret' '~app:*' '+@read' '+@write'
redis-cli -a <secret> PING             # authenticate from the CLI
```

## CONFIG SET / CONFIG REWRITE

`CONFIG SET <param> <value>` changes a setting live (no restart). It is **not**
persistent — `CONFIG REWRITE` writes the running config back into `redis.conf` so
it survives a restart. Always pair them when you want the change to stick.

```bash
redis-cli CONFIG GET maxmemory
redis-cli CONFIG SET maxmemory 1gb
redis-cli CONFIG REWRITE               # persist to redis.conf
```

## INFO and operational visibility

```bash
redis-cli INFO                  # all sections
redis-cli INFO memory           # used_memory, maxmemory, maxmemory_policy, evicted_keys
redis-cli INFO persistence      # rdb_last_save_time, aof_enabled, loading
redis-cli INFO clients          # connected_clients, blocked_clients, maxclients
redis-cli INFO stats            # keyspace_hits/misses, evicted_keys, expired_keys
redis-cli DBSIZE                # number of keys
```

A high `evicted_keys` rate means `maxmemory` is too small for the working set, or
the policy is wrong. `keyspace_hits` vs `keyspace_misses` gives the hit ratio.

## maxclients

```ini
maxclients 10000             # default; capped by the OS file-descriptor limit
```

Redis reserves some FDs for internal use; if the systemd `LimitNOFILE` is lower
than `maxclients + reserve`, Redis lowers `maxclients` at startup and logs it.
Raise the unit's `LimitNOFILE` (drop-in override) to support a higher ceiling.
`INFO clients` shows `connected_clients`; new connections beyond the limit are
refused with an error.
