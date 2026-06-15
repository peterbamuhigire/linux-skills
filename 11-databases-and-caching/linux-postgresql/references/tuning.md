# PostgreSQL: performance tuning (postgresql.conf)

[GROUNDING-GAP: PostgreSQL tuning — official PostgreSQL docs; deepen with
PostgreSQL 16 Administration Cookbook. Apply conservatively and verify live;
these are starting points, not absolutes.]

Edit the right file for your family (or a `conf.d` drop-in to keep the packaged
config pristine):

- RHEL family: `/var/lib/pgsql/data/postgresql.conf`
- Debian/Ubuntu: `/etc/postgresql/<ver>/main/postgresql.conf`

Drop-in approach (both families ship an `include_dir`):

```conf
# postgresql.conf already has: include_dir = 'conf.d'
# Put overrides in conf.d/zz-tuning.conf so they win over earlier includes.
```

Apply changes: most parameters take effect on **reload**; a few (notably
`shared_buffers` and `max_connections`) need a **restart** because the memory is
allocated at startup. Check whether a parameter needs a restart with
`SELECT name, context FROM pg_settings WHERE name = '...';` (`context = postmaster`
means restart).

## The high-impact knobs

### shared_buffers — RESTART

PostgreSQL's own shared memory cache for table/index pages. The single biggest
memory lever.

- Start at **~25% of system RAM** on a dedicated DB host. PostgreSQL also relies
  heavily on the OS page cache, so going much higher rarely helps and can hurt.
- Example for 8 GB RAM: `shared_buffers = 2GB`.

```conf
shared_buffers = 2GB
```

### effective_cache_size — reload (planner hint only)

An **estimate** of how much memory is available for disk caching across
PostgreSQL **and** the OS combined. It allocates nothing — it only tells the
planner how likely index scans are to hit cache, nudging plan choice.

- Set to roughly **50–75% of RAM**.
- Example for 8 GB RAM: `effective_cache_size = 6GB`.

```conf
effective_cache_size = 6GB
```

### work_mem — reload (per-operation, MULTIPLIES)

Memory each sort / hash / merge node may use **per operation, per connection**.
A single complex query can have several such nodes, and many connections run at
once — so the real ceiling is roughly `work_mem x nodes x active connections`.
Setting it large globally is the classic way to OOM a server.

- Keep the global value modest (e.g. **16MB–64MB**).
- Raise it per-session for a known heavy reporting query instead:
  `SET work_mem = '256MB';` for that connection only.

```conf
work_mem = 16MB
```

### maintenance_work_mem — reload

Memory for maintenance operations: `VACUUM`, `CREATE INDEX`, `ALTER TABLE ... ADD
FOREIGN KEY`, and similar. These run few-at-a-time, so this can be much larger
than `work_mem` without the multiplication risk.

- Common range **256MB–1GB**; larger speeds up index builds and vacuums.

```conf
maintenance_work_mem = 512MB
```

### max_connections — RESTART (+ pooling note)

The hard ceiling on concurrent connections. Each backend is a **separate OS
process** with its own memory overhead, so a very high value wastes RAM and adds
scheduling/lock contention — it does not make the server faster.

- Keep it modest (e.g. **100–200**) and put a **connection pooler** in front for
  high client counts.
- **PgBouncer** is the standard lightweight pooler. In `transaction` pooling mode
  a few dozen real backends can serve thousands of client connections. (Pgpool-II
  is an alternative that also does load balancing.)

```conf
max_connections = 100
```

Rule of thumb: scale real DB concurrency to roughly the number of CPU cores plus
the effective disk parallelism; let the pooler absorb the rest.

### wal_buffers — reload

Shared memory for WAL not yet written to disk. The default (`-1`) auto-sizes to
~1/32 of `shared_buffers`, which is usually fine. On very write-heavy systems an
explicit `16MB` can reduce WAL contention.

```conf
wal_buffers = 16MB
```

### Checkpoint settings — reload

Checkpoints flush dirty buffers to the data files. Frequent checkpoints cause
I/O spikes; spacing them out smooths write load at the cost of longer crash
recovery and more WAL retained.

```conf
checkpoint_timeout = 15min        # max time between automatic checkpoints
max_wal_size = 4GB                # soft cap on WAL between checkpoints (raise to spread them out)
min_wal_size = 1GB
checkpoint_completion_target = 0.9 # spread checkpoint I/O over 90% of the interval
```

If logs show "checkpoints are occurring too frequently", raise `max_wal_size`.

## A conservative starting point (8 GB dedicated host)

```conf
shared_buffers              = 2GB
effective_cache_size        = 6GB
work_mem                    = 16MB
maintenance_work_mem        = 512MB
max_connections             = 100
wal_buffers                 = 16MB
checkpoint_timeout          = 15min
max_wal_size                = 4GB
min_wal_size                = 1GB
checkpoint_completion_target = 0.9
```

## Apply and verify

```bash
# shared_buffers / max_connections need a restart; the rest reload:
sudo systemctl restart postgresql
sudo -u postgres psql -c "SELECT pg_reload_conf();"   # for reload-only params

sudo -u postgres psql -c "SHOW shared_buffers;"
sudo -u postgres psql -c "SHOW work_mem;"
sudo -u postgres psql -c "SELECT name, setting, unit, context FROM pg_settings
  WHERE name IN ('shared_buffers','effective_cache_size','work_mem',
                 'maintenance_work_mem','max_connections','wal_buffers');"
```

## Sources

- Official PostgreSQL documentation: "Server Configuration → Resource
  Consumption" and "Write Ahead Log" (`shared_buffers`, `work_mem`,
  `maintenance_work_mem`, `effective_cache_size`, `wal_buffers`, checkpoint
  parameters).
- PgBouncer documentation (connection pooling modes).
- Deepen with: PostgreSQL 16 Administration Cookbook (Packt).
