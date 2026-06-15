# PostgreSQL: logical backup, WAL archiving & point-in-time recovery

[GROUNDING-GAP: WAL/PITR — official PostgreSQL docs. Test the full restore on a
scratch instance before you depend on it.]

Two complementary strategies:

1. **Logical backup** (`pg_dump`/`pg_dumpall`) — portable SQL/archive snapshots,
   restorable to the instant the dump was taken. Good for migrations and
   per-database recovery.
2. **Physical base backup + WAL archiving** — enables **point-in-time recovery
   (PITR)** to *any* moment, by replaying archived WAL on top of a base backup.

## Logical backup: pg_dump / pg_dumpall / pg_restore

`pg_dump` dumps **one database**. `pg_dumpall` dumps the **whole cluster**,
including the cluster-wide objects `pg_dump` cannot see — **roles, tablespaces,
and grants**.

### Formats

| Format | Flag | Restore tool | Notes |
|---|---|---|---|
| **Custom** | `-Fc` / `--format=custom` | `pg_restore` | Compressed; supports selective and parallel restore. **Preferred.** |
| **Directory** | `-Fd` | `pg_restore` | One file per object; supports parallel dump *and* restore (`-j`). |
| **Tar** | `-Ft` | `pg_restore` | Single archive file. |
| **Plain** | `-Fp` (default) | `psql` | Plain SQL text; restore by piping into `psql`. No selective restore. |

```bash
# Single DB, custom format (compressed, supports selective/parallel restore):
sudo -u postgres pg_dump -Fc appdb > appdb.dump
sudo -u postgres pg_dump --format=custom --file=appdb.dump appdb     # equivalent

# Plain SQL (human-readable, restore with psql):
sudo -u postgres pg_dump -Fp appdb > appdb.sql

# Whole cluster + globals (roles, tablespaces) — plain SQL only:
sudo -u postgres pg_dumpall > cluster.sql
sudo -u postgres pg_dumpall --globals-only > globals.sql    # roles/grants only
```

### Restore

```bash
# Custom/tar/directory dumps -> pg_restore:
sudo -u postgres pg_restore -d appdb appdb.dump            # into an existing DB
sudo -u postgres pg_restore -C -d postgres appdb.dump      # -C: create the DB first, then restore
sudo -u postgres pg_restore -j 4 -d appdb appdb.dump       # parallel restore (custom/dir)

# Plain-format dumps -> psql:
sudo -u postgres psql -d appdb -f appdb.sql
sudo -u postgres psql -f cluster.sql                       # full pg_dumpall restore
```

For a full-cluster rebuild: restore `globals.sql` (roles/tablespaces) **first**,
then the per-database custom dumps. Always **verify** by restoring into a scratch
database before trusting a backup.

## WAL archiving & PITR

### Configure (postgresql.conf) — RESTART required

```conf
wal_level = replica                 # 'replica' (or 'logical') keeps enough WAL for PITR
archive_mode = on
archive_command = 'test ! -f /var/lib/pgsql/wal_archive/%f && cp %p /var/lib/pgsql/wal_archive/%f'
```

- `%p` = path of the WAL file to archive; `%f` = its bare filename.
- The `test ! -f ...` guard refuses to overwrite an already-archived segment.
- `archive_command` **must return non-zero on failure** — PostgreSQL retains the
  segment and retries. A command that silently succeeds while losing the file
  breaks recovery. Test it explicitly and monitor `pg_stat_archiver`.

```bash
sudo install -d -o postgres -g postgres /var/lib/pgsql/wal_archive
sudo systemctl restart postgresql
sudo -u postgres psql -c "SHOW wal_level;"
sudo -u postgres psql -c "SELECT * FROM pg_stat_archiver;"   # failed_count should stay 0
```

### Take a base backup

```bash
sudo -u postgres pg_basebackup -D /backup/base -Ft -z -P --wal-method=stream
```

- `-D` target dir, `-Ft` tar format, `-z` gzip, `-P` progress.
- `--wal-method=stream` streams the WAL generated during the backup so the base
  is self-consistent.

Take a fresh base backup periodically; you can only recover forward from a base
backup using the WAL archived **after** it.

### Restore to a point in time

```bash
# 1. Stop PostgreSQL and move the corrupt data dir aside.
sudo systemctl stop postgresql
sudo mv /var/lib/pgsql/data /var/lib/pgsql/data.broken

# 2. Restore the base backup into the (empty) data dir.
sudo install -d -o postgres -g postgres /var/lib/pgsql/data
sudo -u postgres tar -xzf /backup/base/base.tar.gz -C /var/lib/pgsql/data
#   (extract pg_wal.tar.gz into the pg_wal/ subdir too if present)
```

Set recovery parameters in `postgresql.conf`, then create the recovery signal
file (PostgreSQL 12+ replaced the old `recovery.conf` with parameters in
`postgresql.conf` plus a `recovery.signal` file):

```conf
# postgresql.conf
restore_command = 'cp /var/lib/pgsql/wal_archive/%f %p'
recovery_target_time = '2026-06-15 14:29:59'   # stop just before the disaster
# recovery_target_action = 'promote'           # promote when target reached (default)
```

```bash
sudo -u postgres touch /var/lib/pgsql/data/recovery.signal
sudo systemctl start postgresql
```

PostgreSQL replays archived WAL via `restore_command` up to
`recovery_target_time`, then (with the default `promote` action) opens the
database for writes and removes `recovery.signal`. Other targets:
`recovery_target_lsn`, `recovery_target_xid`, `recovery_target_name` (a label set
earlier with `pg_create_restore_point`).

Watch the server log during replay and confirm with:

```bash
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"   # false once promoted
```

## Operational rules

- Archive WAL **off** the database host; a base backup is useless without the WAL
  that follows it.
- Monitor `pg_stat_archiver.failed_count` — a failing `archive_command` silently
  breaks PITR.
- Never delete archived WAL newer than your oldest base backup you still rely on.
- Always rehearse the full restore-and-replay on a scratch instance.

## Sources

- Official PostgreSQL documentation: "Backup and Restore" — `pg_dump`,
  `pg_dumpall`, `pg_restore`, "Continuous Archiving and Point-in-Time Recovery"
  (`wal_level`, `archive_mode`, `archive_command`, `pg_basebackup`,
  `restore_command`, `recovery.signal`, recovery targets).
