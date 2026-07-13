---
name: linux-mysql-mariadb
description: Use when installing, securing, tuning, backing up, restoring, or diagnosing MySQL or MariaDB on Debian/Ubuntu or RHEL-family hosts. Covers InnoDB, logical dumps, binlogs, and PITR; use linux-postgresql for PostgreSQL.
license: MIT
metadata:
  portable: true
  compatible_with: [claude-code, codex]
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# MySQL & MariaDB Operations

## Distro support

Two-family skill. MySQL and MariaDB are wire- and config-compatible forks;
where they differ is noted inline. The split that matters most is the **config
drop-in directory** and the **service/unit name**. The body below uses the
RHEL-family paths (grounded in RHEL 9 Recipes 37 & 39); Debian/Ubuntu paths are
in the matrix and in
[`references/install-and-secure.md`](references/install-and-secure.md).

| Concept | Debian/Ubuntu | RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle) |
|---|---|---|
| Install MariaDB | `apt install mariadb-server` | `dnf install mariadb-server` |
| Install MySQL | `apt install mysql-server` (default-mysql-server) | `dnf install mysql-server` (App Stream, MySQL 8) |
| Service (MySQL) | `mysql` | `mysqld` |
| Service (MariaDB) | `mariadb` | `mariadb` |
| Main config | `/etc/mysql/my.cnf` → includes `mysql.conf.d/` and `mariadb.conf.d/` | `/etc/my.cnf` → includes `/etc/my.cnf.d/` |
| Tuning drop-in | `/etc/mysql/mysql.conf.d/zz-tuning.cnf` | `/etc/my.cnf.d/zz-tuning.cnf` |
| Data dir | `/var/lib/mysql` | `/var/lib/mysql` |
| Client config (root) | `/root/.my.cnf` or `mariadb`/`mysql` socket auth | `/root/.my.cnf` or socket auth |
| Secure script | `mysql_secure_installation` | `mysql_secure_installation` |
| Logs | `journalctl -u mysql` / `mariadb` | `journalctl -u mysqld` / `mariadb` |

Both families ship `mysqldump`, `mysql`, and `mysqlbinlog` under the same names.
On RHEL 9, MySQL and MariaDB **conflict** — you cannot install both (RHEL 9
Recipe 39). Use the `svc_name`/`pkg_install` helpers from `common.sh` in
`sk-*` scripts so one script runs on both families; see
[`docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

> [GROUNDING-GAP: DB tuning/PITR — InnoDB tuning, binary logging and
> point-in-time recovery are NOT in the corpus; grounded on official
> MySQL 8 / MariaDB Server docs; deepen with High Performance MySQL 4e
> (O'Reilly). Install/secure is grounded in RHEL 9 Recipes 37 & 39.]

<!-- dual-compat-start -->
## Use When

- Installing and securing a fresh MySQL or MariaDB server.
- Tuning InnoDB memory and connection limits for a workload.
- Taking consistent logical backups or enabling point-in-time recovery.
- Diagnosing connection limits, slow queries, or replication/binlog state.

## Do Not Use When

- The task is the surrounding LAMP web tier (PHP-FPM, vhosts); use `linux-webstack`.
- The task is Redis/Memcached caching; use `linux-inmemory-stores`.
- The task is generic offsite archive rotation only; use `linux-rsync-sync` or `linux-archive-integrity`.

## Required Inputs

| Artefact | Required? | Source | If absent |
|---|---|---|---|
| Engine/version, distro, topology, and service objective | yes | Inventory and database owner | Stop before installation, upgrade, or config changes. |
| Workload measurements and host memory budget | tuning only | Metrics and capacity plan | Limit work to read-only diagnostics; do not invent tuning values. |
| RPO/RTO, destination, retention, and encryption policy | backup/PITR | Recovery policy | Do not claim recoverability; provide a qualified design only. |
| Maintenance window and rollback | mutation | Approved change record | Do not restart or modify production. |

## Capability Contract

Diagnostics default to read-only database and host access. Package changes, SQL writes, config edits, restarts, backup rotation, restores, and binlog replay require explicit authority. Credentials must come from the approved secret provider and never appear in commands or evidence.

## Degraded Mode

Without database access, return version-specific commands and label values unverified. Without workload evidence, do not prescribe numeric tuning. Without an isolated restore target, mark recovery `not proven`.

## Decision Rules

| Choice | Action | Failure or risk avoided |
|---|---|---|
| MySQL versus MariaDB | Preserve the installed engine unless migration evidence authorises a change; never install conflicting RHEL packages together. | Accidental fork migration or package conflict. |
| Logical backup | Use `--single-transaction` for InnoDB and include required routines, events, triggers, and grants. | Inconsistent or incomplete restore. |
| PITR | Enable, retain, and monitor binlogs when RPO is shorter than the dump interval. | Recovery gap between dumps. |
| Tuning | Change one justified drop-in at a time and load-test it. | Memory exhaustion and untraceable regressions. |

## Workflow

1. Confirm inputs, compatibility, authority, maintenance window, and rollback; stop on an unidentified engine or missing recovery objective.
2. Inspect package, unit, config includes, variables, data size, workload, and backup/binlog state read-only.
3. Decide hardening, tuning, dump, and PITR actions with the decision table.
4. With authority, install the family package and harden accounts before network exposure.
5. Apply minimal tuning through the family drop-in directory; validate before restart.
6. Create the logical backup and capture binlog coordinates when PITR is required.
7. Restore into an isolated instance, reconcile objects and row counts, and test binlog replay. On failure, stop, retain evidence, revert the drop-in or prior service state, and keep the last known-good backup.

## Quality Standards

- Tune via a numbered drop-in file; keep the packaged config pristine.
- Always `--single-transaction` for InnoDB dumps (consistent, non-locking).
- A backup you have not test-restored is not a backup.
- Evidence identifies engine/version, config source, checksum, restore target, and recovery result while redacting credentials.

## Anti-Patterns

- Changing the database fork implicitly. Fix: preserve the installed engine unless migration is explicitly approved.
- Tuning from host RAM alone. Fix: combine workload and per-connection evidence with OS headroom.
- Editing vendor configuration. Fix: use one owned ordered drop-in and record rollback.
- Treating dump completion as recovery proof. Fix: restore to isolation and reconcile objects/data.
- Passing database passwords on the command line. Fix: use socket auth or a protected option file.

- Leaving anonymous users, the test database, or remote root login. Correction: remove them before exposure and verify grants.
- Sizing `innodb_buffer_pool_size` to all RAM. Correction: use workload evidence and leave OS/connection headroom.
- Using dumps alone for a shorter RPO. Correction: retain tested binlogs and coordinates.
- Editing vendor `my.cnf`. Correction: use an owned, ordered drop-in with a clean rollback.
- Treating a successful dump as recovery proof. Correction: restore to scratch and reconcile schema and data.
- Passing passwords on the command line. Correction: use socket auth or a protected option file from the secret workflow.

## Outputs

| Artefact | Consumer | Acceptance condition |
|---|---|---|
| Database change record | DBA/operator | Names engine/version, drop-in, before/after values, validation, restart, and rollback. |
| Backup set and manifest | Recovery operator | Dump is checksummed, protected as required, retained at the approved destination, and includes required objects. |
| Restore/PITR report | Service owner | Scratch restore succeeds and the declared recovery point is demonstrated or marked unproven. |

## Evidence Produced

| Artefact | Acceptance |
|---|---|
| Database recovery evidence | Contains redacted config/version, backup checksum, binlog coordinates, restore logs, reconciliation, and health result. |

Capture redacted variables/config, server version, backup checksum and manifest, binlog coordinates/retention, restore logs, reconciliation counts, and final health checks.

## Worked Example

For a MariaDB service with a 15-minute RPO, take a consistent dump, record its binlog position, restore it to scratch, and replay to a chosen timestamp. Do not claim PITR until replay and reconciliation pass.

## Install & secure

```bash
# RHEL family (App Stream) — MySQL 8 (Recipe 37) or MariaDB 10.x (Recipe 39)
sudo dnf install mysql-server          # MySQL
sudo systemctl enable --now mysqld
#   — or —
sudo dnf install mariadb-server        # MariaDB (cannot coexist with mysql-server)
sudo systemctl enable --now mariadb

# Debian/Ubuntu
sudo apt install mariadb-server        # or: mysql-server
sudo systemctl enable --now mariadb    # unit is 'mysql' for mysql-server

# Both families — harden before exposing (sets root pw, drops anon users,
# test DB, and remote root login):
sudo mysql_secure_installation
```

Full per-distro detail, socket vs password auth, and creating an app user with
least privilege: [`references/install-and-secure.md`](references/install-and-secure.md).

## Config files

Never edit the packaged `my.cnf`. Drop a numbered file in the include dir so it
sorts last and wins:

```bash
# RHEL family
sudo install -m 0644 /dev/null /etc/my.cnf.d/zz-tuning.cnf
# Debian/Ubuntu
sudo install -m 0644 /dev/null /etc/mysql/mysql.conf.d/zz-tuning.cnf
```

## InnoDB tuning

```ini
[mysqld]
# ~50-70% of RAM on a dedicated DB host (the single most impactful knob).
innodb_buffer_pool_size = 4G

# Redo log size. Larger = fewer flushes, faster writes, slower crash recovery.
# MySQL 8.0.30+: prefer innodb_redo_log_capacity instead of innodb_log_file_size.
innodb_log_file_size    = 512M

# One file per table — easier reclaim of space, per-table operations.
innodb_file_per_table   = ON

# Durability: 1 = ACID (flush each commit). 2 trades crash-safety for speed.
innodb_flush_log_at_trx_commit = 1

# Connection ceiling. Each connection costs memory — size to the app's real
# concurrency, not an arbitrary large number.
max_connections         = 200
```

Apply, then verify live values:
```bash
sudo systemctl restart mysqld    # or 'mariadb' / 'mysql'
mysql -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
mysql -e "SHOW VARIABLES LIKE 'max_connections';"
```

Rationale, sizing math, redo-log capacity changes across versions, and
`mysqltuner`-style review: [`references/tuning-innodb.md`](references/tuning-innodb.md).

## Logical backup (mysqldump)

```bash
# Consistent, non-locking InnoDB dump of one database:
mysqldump --single-transaction --routines --triggers --events mydb > mydb.sql

# All databases (combined), with binlog coordinate for PITR (see below):
mysqldump --all-databases --single-transaction --routines --triggers --events \
          --source-data=2 > all.sql        # --master-data=2 on older versions

# Restore:
mysql mydb < mydb.sql
```

## Binary logging & point-in-time recovery (PITR)

A nightly dump only restores to the dump instant. To recover to *any* point,
combine a base dump with the binary logs written since:

```ini
[mysqld]
log_bin       = /var/lib/mysql/binlog     # MariaDB: log_bin = mariadb-bin
server_id     = 1
binlog_format = ROW
expire_logs_days = 7                        # MySQL 8: binlog_expire_logs_seconds
```

```bash
# 1. Base dump records the starting binlog coordinate:
mysqldump --all-databases --single-transaction --source-data=2 > base.sql

# 2. Disaster strikes. Restore the base dump:
mysql < base.sql

# 3. Replay binlogs from the recorded position up to just before the bad event:
mysqlbinlog --stop-datetime="2026-06-15 14:29:59" \
            /var/lib/mysql/binlog.000007 | mysql
```

Full PITR procedure, finding the right binlog/position, `--start-position`,
GTID notes, and MariaDB differences:
[`references/binlog-and-pitr.md`](references/binlog-and-pitr.md).

## Health & monitoring

```bash
mysqladmin status                                  # uptime, threads, qps
mysql -e "SHOW GLOBAL STATUS LIKE 'Threads_connected';"
mysql -e "SHOW ENGINE INNODB STATUS\G" | head -40  # locks, buffer pool, I/O
mysql -e "SHOW PROCESSLIST;"                        # live queries
```

<!-- dual-compat-end -->

## References

- [`references/install-and-secure.md`](references/install-and-secure.md)
- [`references/tuning-innodb.md`](references/tuning-innodb.md)
- [`references/binlog-and-pitr.md`](references/binlog-and-pitr.md)

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-mysql-mariadb
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-mysql-health | scripts/sk-mysql-health.sh | yes | Read-only health check: connectivity, uptime/qps, threads vs `max_connections`, InnoDB buffer-pool hit ratio, binary-logging state, slow-query count. Both families. PASS/WARN/FAIL summary. |
| sk-mysql-backup | scripts/sk-mysql-backup.sh | no | Dump all databases (`--single-transaction`, per-db + combined), compress, GPG-encrypt, upload via rclone, rotate local + remote copies. Interactive by default; `--yes` for cron. Runs on both families. |
