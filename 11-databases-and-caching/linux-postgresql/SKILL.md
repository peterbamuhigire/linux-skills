---
name: linux-postgresql
description: Use when installing, authenticating, tuning, backing up, restoring, or diagnosing PostgreSQL on Debian/Ubuntu or RHEL-family hosts. Covers pg_hba.conf, logical backups, WAL, and PITR; use linux-mysql-mariadb for MySQL/MariaDB.
license: MIT
metadata:
  portable: true
  compatible_with: [claude-code, codex]
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

<!-- dual-compat-start -->
## Use When

- Installing and initializing a PostgreSQL cluster on either family.
- Tuning memory (`shared_buffers`, `work_mem`, `effective_cache_size`) and `max_connections`.
- Configuring client authentication in `pg_hba.conf`.
- Taking logical backups (`pg_dump`/`pg_dumpall`) or setting up WAL archiving + PITR.

## Do Not Use When

- The engine is MySQL/MariaDB; use `linux-mysql-mariadb`.
- The store is Redis/Memcached; use `linux-inmemory-stores`.
- The task is only offsite archive rotation; use `linux-rsync-sync`.

## Required Inputs

| Artefact | Required? | Source | If absent |
|---|---|---|---|
| Version, distro, cluster path/name, topology, and objective | yes | Inventory and database owner | Stop before initialization, upgrade, or mutation. |
| Client identities, CIDRs, and auth policy | auth work | Topology and security policy | Retain local peer access; do not add host rules. |
| Workload metrics and memory/concurrency budget | tuning | Metrics and capacity plan | Diagnose read-only; do not invent values. |
| RPO/RTO, archive destination, retention, and restore target | backup/PITR | Recovery policy | Mark recovery unproven and do not enable incomplete archiving. |

## Capability Contract

Inspection defaults to read-only host and database access. Initialization, role/data changes, config edits, reloads/restarts, archive writes, restores, and WAL replay require explicit authority. Credentials use the approved secret path and stay out of evidence.

## Degraded Mode

Without cluster access, return version- and family-qualified commands only. Without workload evidence, do not recommend numeric tuning. Without an isolated restore or archived WAL access, separate backup creation from unassessed recovery.

## Decision Rules

| Choice | Action | Failure or risk avoided |
|---|---|---|
| Authentication | Prefer peer locally and SCRAM for defined remote clients; reject broad `trust` rules. | Unauthenticated access. |
| Logical backup | Use custom format for selective/parallel restore; export globals when roles/tablespaces matter. | Missing cluster-level objects. |
| PITR | Pair a physical base backup with continuously verified WAL archiving. | Unusable recovery chain. |
| Connection pressure | Use a pooler before raising `max_connections` beyond measured need. | Per-backend memory exhaustion. |

## Workflow

1. Confirm inputs, exact cluster/version, authority, window, and rollback; stop if the target cluster is ambiguous.
2. Inspect cluster status, config locations, `pg_hba.conf` order, runtime settings, workload, and archive state read-only.
3. Decide authentication, tuning, backup format, and PITR actions with the decision table.
4. With authority, install/initialize only the intended cluster and harden remote access before exposure.
5. Apply the narrow config/auth change, validate it, reload when supported, and restart only when required.
6. Create logical/globals backups or a base backup plus verified WAL archive.
7. Restore to isolation, reconcile roles/schema/data, and test target-time recovery. On failure, stop, preserve the archive chain, restore prior config, and do not declare readiness.

## Quality Standards

- Prefer `scram-sha-256` over `md5`/`trust` in `pg_hba.conf`.
- `shared_buffers` ~25% of RAM; `effective_cache_size` ~50–75% (a hint, not an allocation).
- Use `pg_dump -Fc` (custom format) so `pg_restore` can do selective/parallel restores.
- Record exact versions, cluster path, config source, checksum, restore target, and result.

## Anti-Patterns

- Using network `trust`. Fix: scope client CIDRs and require SCRAM authentication.
- Setting large global `work_mem`. Fix: model concurrent operators and tune narrowly.
- Raising `max_connections` instead of pooling. Fix: measure concurrency and use a pooler where appropriate.
- Allowing silent WAL archive failure. Fix: monitor, retrieve, and target-time test the archive chain.
- Backing up data without required globals. Fix: include roles/tablespaces and prove an isolated restore.

- Using `trust` for network clients. Correction: define narrow CIDRs and SCRAM.
- Setting large global `work_mem`. Correction: model concurrent sort/hash operations and tune narrowly.
- Raising `max_connections` to solve pooling failures. Correction: measure concurrency and use a pooler.
- Allowing an archive command to overwrite or silently fail. Correction: make it idempotent, monitored, and retrieval-tested.
- Omitting required roles from a database backup. Correction: pair `pg_dump -Fc` with the needed globals export.
- Trusting backup completion without recovery. Correction: restore to isolation and reconcile expected objects/data.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Cluster change record | DBA/operator | Names cluster/version, ordered auth/config change, validation, reload/restart, and rollback. |
| Backup/archive manifest | Recovery operator | Checksums logical/globals or base-backup/WAL artefacts and records retention/location. |
| Restore/PITR report | Service owner | Isolated restore reconciles expected roles/schema/data; recovery point is demonstrated or marked unproven. |

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| PostgreSQL recovery evidence | Contains redacted auth/settings, cluster version, manifests/checksums, WAL health, restore logs, and reconciliation. |

Capture redacted effective settings and auth evidence, cluster/version output, manifests/checksums, WAL health, restore logs, reconciliation queries, and final service health.

## Worked Example

For a one-hour RPO, confirm the archive command, take a base backup, preserve required WAL, restore to an isolated cluster, and recover to a timestamp inside the test window. `pg_basebackup` success alone is not PITR evidence.

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

<!-- dual-compat-end -->

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
