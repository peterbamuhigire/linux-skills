---
name: linux-postgresql
description: Operate PostgreSQL across both major Linux families — install (postgresql-server + postgresql-setup --initdb on RHEL App Stream; postgresql + auto-init on Debian/Ubuntu), tune postgresql.conf (shared_buffers, work_mem, effective_cache_size, max_connections), configure client authentication in pg_hba.conf, back up with pg_dump / pg_dumpall / pg_restore, and set up WAL archiving + point-in-time recovery (archive_mode, archive_command, base backups via pg_basebackup). Includes a backup sk-* script.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# PostgreSQL Operations

## Distro support

Two-family skill. The big difference is **initialization** and the **data /
config directory layout**. On RHEL the cluster is not auto-created — you must
run `postgresql-setup --initdb` (RHEL 9 Recipe 38), and the config lives under
the data dir. On Debian/Ubuntu the package auto-creates a cluster and config
lives under `/etc/postgresql/<ver>/<cluster>/`. The body uses RHEL paths
(grounded in Recipe 38); Debian paths are in the matrix and references.

| Concept | Debian/Ubuntu | RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) |
|---|---|---|
| Install | `apt install postgresql` | `dnf install postgresql-server` |
| Initialize cluster | automatic on install | `sudo postgresql-setup --initdb` (Recipe 38) |
| Service | `postgresql` | `postgresql` |
| Enable on boot | `systemctl enable --now postgresql` | `systemctl enable --now postgresql.service` |
| Data dir (`PGDATA`) | `/var/lib/postgresql/<ver>/main` | `/var/lib/pgsql/data` |
| `postgresql.conf` | `/etc/postgresql/<ver>/main/postgresql.conf` | `/var/lib/pgsql/data/postgresql.conf` |
| `pg_hba.conf` | `/etc/postgresql/<ver>/main/pg_hba.conf` | `/var/lib/pgsql/data/pg_hba.conf` |
| Admin user | `postgres` (peer auth: `sudo -u postgres psql`) | `postgres` (peer auth: `sudo -u postgres psql`) |
| Cluster tooling | `pg_ctlcluster`, `pg_lsclusters` | `systemctl`, `pg_ctl` |
| Default version | distro current | RHEL 9: PostgreSQL 13 (App Stream; newer streams available) |

Both families ship `psql`, `pg_dump`, `pg_dumpall`, `pg_restore`,
`pg_basebackup`, and connect over the same `postgres` superuser via **peer
auth** locally. Use `pkg_install`/`svc_name` from `common.sh` in `sk-*` scripts;
the service name `postgresql` is identical on both. See
[`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

> [GROUNDING-GAP: DB tuning/WAL PITR — postgresql.conf tuning, WAL archiving and
> point-in-time recovery are NOT in the corpus; grounded on official PostgreSQL
> documentation; deepen with PostgreSQL 16 Administration Cookbook (Packt).
> Install/init/pg_hba is grounded in RHEL 9 Recipe 38.]

## Use when

- Installing and initializing a PostgreSQL cluster on either family.
- Tuning memory (`shared_buffers`, `work_mem`, `effective_cache_size`) and `max_connections`.
- Configuring client authentication in `pg_hba.conf`.
- Taking logical backups (`pg_dump`/`pg_dumpall`) or setting up WAL archiving + PITR.

## Do not use when

- The engine is MySQL/MariaDB; use `linux-mysql-mariadb`.
- The store is Redis/Memcached; use `linux-inmemory-stores`.
- The task is only offsite archive rotation; use `linux-rsync-sync`.

## Required inputs

- PostgreSQL version and the family (init differs).
- Host RAM (drives `shared_buffers` / `effective_cache_size`).
- Auth model needed in `pg_hba.conf` (peer, scram-sha-256, host ranges).
- Backup target and whether WAL archiving / PITR is required.

## Workflow

1. Install; on RHEL run `postgresql-setup --initdb`; enable and start the unit.
2. Set authentication in `pg_hba.conf`; reload (`SELECT pg_reload_conf();`).
3. Tune memory in `postgresql.conf` (or a `conf.d` drop-in); restart for `shared_buffers`.
4. Back up with `pg_dump`/`pg_dumpall`; for PITR enable WAL archiving + `pg_basebackup`.
5. Verify: restore into a scratch database before trusting the backup.

## Quality standards

- Prefer `scram-sha-256` over `md5`/`trust` in `pg_hba.conf`.
- `shared_buffers` ~25% of RAM; `effective_cache_size` ~50–75% (a hint, not an allocation).
- Use `pg_dump -Fc` (custom format) so `pg_restore` can do selective/parallel restores.

## Anti-patterns

- `trust` auth on a `host` line reachable from the network.
- Setting `work_mem` huge globally — it is *per sort/hash node per connection* and multiplies.
- WAL archiving with an `archive_command` that can silently fail (always test its exit status).

## Outputs

- The config values changed and which file (and whether a reload or restart was needed).
- The backup command/format and restore-verification result.
- WAL archiving / PITR posture if applicable.

## Install & initialize

```bash
# RHEL family (Recipe 38) — cluster is NOT auto-created:
sudo dnf install postgresql-server
sudo postgresql-setup --initdb
sudo systemctl enable --now postgresql.service

# Debian/Ubuntu — package auto-creates a cluster:
sudo apt install postgresql
sudo systemctl enable --now postgresql
```

Connect as the superuser via peer auth, create a role and DB:
```bash
sudo -u postgres psql
```
```sql
CREATE USER appuser WITH PASSWORD 'STRONG_PASSWORD';   -- Recipe 38
CREATE DATABASE appdb OWNER appuser;
GRANT ALL PRIVILEGES ON DATABASE appdb TO appuser;
```

Full per-distro detail and role privileges (SUPERUSER, LOGIN, CREATEDB,
CREATEROLE — Recipe 38): [`references/install-and-auth.md`](references/install-and-auth.md).

## Authentication (pg_hba.conf)

`pg_hba.conf` is matched **top-down, first match wins**. Order specific rules
before broad ones.

```conf
# TYPE  DATABASE  USER      ADDRESS          METHOD
local   all       postgres                   peer            # local socket as OS user
local   all       all                        scram-sha-256
host    appdb     appuser   10.0.0.0/24      scram-sha-256   # specific app subnet
host    all       all       0.0.0.0/0        reject          # default deny
```

```bash
sudo -u postgres psql -c "SELECT pg_reload_conf();"   # reload after edits (no restart)
```

Methods and migration off `md5`: [`references/install-and-auth.md`](references/install-and-auth.md).

## Tuning (postgresql.conf)

```conf
# ~25% of RAM. Requires a RESTART (allocated at startup).
shared_buffers = 2GB

# Planner HINT for total OS+PG cache available. Not allocated. ~50-75% of RAM.
effective_cache_size = 6GB

# Memory PER sort/hash operation PER connection. Multiplies — keep modest.
work_mem = 16MB

# For VACUUM/CREATE INDEX. Can be larger (one at a time, few concurrent).
maintenance_work_mem = 512MB

# Connection ceiling. Each backend is a process — use a pooler (PgBouncer)
# rather than a very high number.
max_connections = 100
```

Apply: `shared_buffers`/`max_connections` need a restart; most others reload.
```bash
sudo systemctl restart postgresql        # for shared_buffers, max_connections
sudo -u postgres psql -c "SHOW shared_buffers;"
```

Sizing math, `work_mem` multiplication risk, and pooling:
[`references/tuning.md`](references/tuning.md).

## Logical backup (pg_dump / pg_dumpall / pg_restore)

```bash
# Single DB, custom format (compressed, supports selective/parallel restore):
sudo -u postgres pg_dump -Fc appdb > appdb.dump

# All databases + globals (roles, tablespaces) — plain SQL:
sudo -u postgres pg_dumpall > cluster.sql
sudo -u postgres pg_dumpall --globals-only > globals.sql   # roles/grants only

# Restore a custom-format dump (creates objects; -C to create the DB):
sudo -u postgres pg_restore -d appdb appdb.dump
sudo -u postgres pg_restore -C -d postgres appdb.dump      # create DB then restore
```

`pg_dumpall` is needed for cluster-wide objects (roles, tablespaces) that
`pg_dump` does not capture. Full matrix: [`references/backup-and-pitr.md`](references/backup-and-pitr.md).

## WAL archiving & point-in-time recovery (PITR)

A logical dump restores to the dump instant. For recovery to *any* point, take
a physical **base backup** and archive **WAL** segments continuously:

```conf
# postgresql.conf
wal_level = replica
archive_mode = on
archive_command = 'test ! -f /var/lib/pgsql/wal_archive/%f && cp %p /var/lib/pgsql/wal_archive/%f'
```

```bash
# Base backup (physical, restorable to any later point with archived WAL):
sudo -u postgres pg_basebackup -D /backup/base -Ft -z -P --wal-method=stream
```

Restore = restore the base backup, set `restore_command` + `recovery_target_time`,
let PostgreSQL replay WAL to the target. Full procedure (signal files, targets,
`archive_command` failure handling): [`references/backup-and-pitr.md`](references/backup-and-pitr.md).

## Health & monitoring

```bash
sudo -u postgres psql -c "SELECT version();"
sudo -u postgres psql -c "SELECT count(*) FROM pg_stat_activity;"   # connections
sudo -u postgres psql -c "SELECT datname, numbackends FROM pg_stat_database;"
sudo -u postgres psql -c "SHOW max_connections;"
```

## References

- [`references/install-and-auth.md`](references/install-and-auth.md)
- [`references/tuning.md`](references/tuning.md)
- [`references/backup-and-pitr.md`](references/backup-and-pitr.md)

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-postgresql
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-pg-backup | scripts/sk-pg-backup.sh | yes | Logical backup of one or all databases via `pg_dump -Fc` (+ `pg_dumpall --globals-only` for roles), timestamped, compressed, rotated by retention days. Optional WAL-archive sanity check. Interactive by default; `--yes` for cron. Both families. |
