---
name: linux-mysql-mariadb
description: Operate MySQL and MariaDB across both major Linux families — install (mysql-server on RHEL App Stream, mariadb-server on both, default-distro/mysql-server on Debian/Ubuntu), secure with mysql_secure_installation, and locate config (drop-ins in /etc/mysql/mysql.conf.d/ on Debian vs /etc/my.cnf.d/ on RHEL). InnoDB tuning (innodb_buffer_pool_size, innodb_log_file_size, max_connections). Logical backup with mysqldump --single-transaction. Binary logging and point-in-time recovery (binlog, --master-data / --source-data). Health checks and automated encrypted offsite backup via a sk-* script.
license: MIT
metadata:
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

## Use when

- Installing and securing a fresh MySQL or MariaDB server.
- Tuning InnoDB memory and connection limits for a workload.
- Taking consistent logical backups or enabling point-in-time recovery.
- Diagnosing connection limits, slow queries, or replication/binlog state.

## Do not use when

- The task is the surrounding LAMP web tier (PHP-FPM, vhosts); use `linux-webstack`.
- The task is Redis/Memcached caching; use `linux-inmemory-stores`.
- The task is generic offsite archive rotation only; use `linux-rsync-sync` or `linux-archive-integrity`.

## Required inputs

- Which engine (MySQL or MariaDB) and version.
- Host RAM and the intended `innodb_buffer_pool_size` budget.
- Backup destination and whether PITR (binary logging) is required.

## Workflow

1. Install the server package for the family; start and enable the unit.
2. Run `mysql_secure_installation` before exposing the instance.
3. Add tuning as a drop-in in the family's `*.cnf.d/` dir — never edit the shipped `my.cnf`.
4. Set up logical backups (`mysqldump --single-transaction`) and, if PITR is needed, enable binary logging.
5. Verify: restore a dump into a scratch schema before trusting the backup.

## Quality standards

- Tune via a numbered drop-in file; keep the packaged config pristine.
- Always `--single-transaction` for InnoDB dumps (consistent, non-locking).
- A backup you have not test-restored is not a backup.

## Anti-patterns

- Leaving anonymous users, the test DB, or remote root login after install.
- Sizing `innodb_buffer_pool_size` to 100% of RAM (starves the OS).
- Relying on `mysqldump` alone when the RPO requires PITR — you also need binlogs.

## Outputs

- The exact config drop-in written and the variable values chosen.
- The backup command, schedule, and restore-verification result.
- Binary-log / PITR posture if applicable.

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
