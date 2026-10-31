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

### Keep dumps private

A dump holds the data, and the `pg_dumpall --globals-only` output holds role
password hashes (pg_dumpall includes passwords unless `--no-role-passwords` is
given, and says so in its manual). Create both mode `0600` in a `0700` directory
owned by the account that will restore them. `sk-pg-backup` does this: it writes
through a private staging directory and renames a file into place only after
`pg_restore --list` can read it. For a manual dump, set `umask 077` first and
let the shell that owns the directory open the file:

```bash
umask 077
install -d -m 0700 /var/backups/postgresql
sudo -u postgres pg_dump --format=custom -- appdb > /var/backups/postgresql/appdb.dump
```

The redirect is opened by your shell, not by `postgres`, so the file belongs to
you and has your umask's mode. Dumps are not encrypted: protect any copy of the
directory (offsite, snapshots) the way you protect the database itself.

### Verify a logical backup

A dump that was written is not a backup until it has been restored. Do this on a
scratch PostgreSQL instance of the same major version or newer, never on the
source cluster: restoring globals there would alter its roles. Record, without
credentials or row values you are not cleared to copy: source `server_version`,
dump start and end times, file names, sizes, mode and `sha256sum`.

1. Readability, no server needed: `pg_restore --list appdb.dump > /dev/null`.
2. Restore roles first, then the database, timing the whole step. The 0600 files
   belong to the backup account, so read them on standard input from your own
   shell:

   ```bash
   time sudo -u postgres psql -X postgres < globals_<timestamp>.sql
   time sudo -u postgres pg_restore --exit-on-error --create --dbname=postgres < appdb_<timestamp>.dump
   ```

   Expect a `role ... already exists` error for the bootstrap superuser from the
   globals script: the pg_dumpall manual calls it harmless, so do not use `ON_ERROR_STOP` for that
   file. A parallel restore (`-j`) cannot read standard input (pg_restore manual:
   the input must be a regular file or directory); for it, copy the dump to a
   directory the restore user owns on the scratch host and restore from there.
3. Reconcile with the source as it was at dump time: schemas, table and index
   counts, extensions (`\dx`), functions and triggers, sequences, and row counts
   for the tables the application cannot live without. Run `ANALYZE`, then one
   read-only application query. Counts on a live source drift after the dump;
   compare against figures taken at dump time, or state the tolerated drift.
4. Record target version, commands, elapsed time (the restore-time input for
   this data size), results and any failure. If any step fails, mark recovery
   unproven and keep the last known-good backup.

Status: this procedure follows the current PostgreSQL manuals for `pg_restore`
and `pg_dumpall` (pages read 2026-10-31; the manual's release number was not recorded).
Lab result, 2026-10-31: the commands above ran as written on a scratch instance in
Debian 12 (PostgreSQL 15.19) and Fedora 44 (PostgreSQL 18.6), each restoring a backup
that `sk-pg-backup` made on a separate source instance (a 5 000-row table with a trigger,
view, index, extension and grants, plus a database named `lab odd;db`). The globals file
restored with exit 0 and the documented `role "postgres" already exists` error; both
databases restored in about 0.3 s; row counts, a content checksum, indexes, triggers, views,
extensions, the sequence value, owner and grants equalled the figures taken at dump time. A
second `--create` restore into the same instance and a truncated dump both failed with a
non-zero exit, and `pg_restore -j` from standard input failed with the manual's message.
`sk-pg-backup` itself was exercised on both sources: modes 0700 and 0600, repeated runs,
retention, and controlled failures (PostgreSQL stopped, unwritable path, write failure,
truncated dump). Repeat it with `LINUX_SKILLS_LAB=1 python -m pytest tests/test_distro_labs.py`
(rootless Podman, local images, evidence in `docs/kaizen/2026-10-linux-lab-wave/`).
`NOT_ASSESSED`: production data sizes and restore times, PostgreSQL 14 and 16 to 17 servers,
a restore into a newer major version, and the RHEL 9 and 10 packages.

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
