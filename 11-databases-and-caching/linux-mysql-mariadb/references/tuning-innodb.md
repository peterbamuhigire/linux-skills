# InnoDB tuning

[GROUNDING-GAP: DB tuning — not in the corpus; grounded on official MySQL 8 /
MariaDB Server reference manuals; deepen with High Performance MySQL 4e
(O'Reilly, Schwartz et al.). Apply conservatively and verify live.]

Tune via a numbered drop-in so the packaged config stays pristine:

- RHEL family: `/etc/my.cnf.d/zz-tuning.cnf`
- Debian/Ubuntu: `/etc/mysql/mysql.conf.d/zz-tuning.cnf`

`zz-` makes it sort last, so its values win over earlier includes.

## The high-impact knobs

### innodb_buffer_pool_size

The cache for table and index data. The single biggest performance lever on a
write/read-heavy InnoDB workload.

- Dedicated DB host: **50–70% of RAM**. Leave headroom for the OS, per-connection
  buffers, and (on a shared box) other services.
- Shared host (DB + web on one box): be conservative — 25–40%.
- Example for a 8 GB dedicated host: `innodb_buffer_pool_size = 5G`.

Check the hit ratio (want > 99% on a warm cache):
```sql
SHOW ENGINE INNODB STATUS\G   -- "Buffer pool hit rate" line
```

### innodb_log_file_size / innodb_redo_log_capacity

Redo log size. Bigger = fewer checkpoint flushes = better write throughput, at
the cost of longer crash recovery.

- **MySQL 8.0.30+**: use `innodb_redo_log_capacity` (dynamic, supersedes the old
  variable). E.g. `innodb_redo_log_capacity = 1G`.
- **Older MySQL / MariaDB**: `innodb_log_file_size` (e.g. `512M`). Changing it
  requires a clean restart.

### max_connections

The hard ceiling on simultaneous client connections. Each costs memory
(per-thread buffers). Size to the application's *real* peak concurrency plus a
margin — not an arbitrary 1000.

```sql
SHOW STATUS LIKE 'Max_used_connections';   -- high-water mark since start
SHOW STATUS LIKE 'Threads_connected';      -- right now
```

If `Max_used_connections` approaches `max_connections`, either raise it (if RAM
allows) or add a connection pool (ProxySQL / app-side pooler).

### innodb_flush_log_at_trx_commit

Durability vs speed:
- `1` (default): full ACID — flush + fsync on every commit. Safest.
- `2`: flush each commit but fsync once per second — survives a *process* crash,
  may lose ~1s on an *OS/power* crash. Faster.
- `0`: fsync once per second regardless — fastest, least safe.

Keep `1` for anything with real data; `2` only when you accept the risk.

## A conservative starting drop-in

```ini
[mysqld]
innodb_buffer_pool_size        = 4G
innodb_redo_log_capacity       = 1G        # or innodb_log_file_size = 512M (older)
innodb_file_per_table          = ON
innodb_flush_log_at_trx_commit = 1
max_connections                = 200
slow_query_log                 = ON
slow_query_log_file            = /var/log/mysql/slow.log
long_query_time                = 2
```

## Verify after restart

```bash
sudo systemctl restart mysqld     # or 'mariadb' / 'mysql' per family+engine
mysql -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
mysql -e "SHOW VARIABLES LIKE 'innodb_redo_log_capacity';"
mysql -e "SHOW VARIABLES LIKE 'max_connections';"
```

`sk-mysql-health` reports the buffer-pool hit ratio and connection headroom
against `max_connections` non-destructively.
