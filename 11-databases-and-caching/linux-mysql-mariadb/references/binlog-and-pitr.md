# Binary logging & point-in-time recovery (PITR)

[GROUNDING-GAP: PITR — not in the corpus; grounded on official MySQL 8 /
MariaDB Server reference manuals; deepen with High Performance MySQL 4e.
Apply conservatively and test the full restore on a scratch instance first.]

A logical dump (`mysqldump`) only restores you to the instant the dump was
taken. To recover to **any point in time** — e.g. just before an accidental
`DROP TABLE` at 14:30 — you need:

1. A periodic **base dump** that records its starting binary-log coordinate.
2. **Binary logs** capturing every change since that dump.

Recovery = restore the base dump, then replay binlog events from the recorded
coordinate up to (but not including) the bad event.

## Enable binary logging

Drop-in (`/etc/my.cnf.d/zz-tuning.cnf` on RHEL, `mysql.conf.d/` on Debian):

```ini
[mysqld]
# MySQL 8
log_bin                    = /var/lib/mysql/binlog
server_id                  = 1
binlog_format              = ROW
binlog_expire_logs_seconds = 604800        # 7 days

# MariaDB equivalent:
#   log_bin     = /var/lib/mysql/mariadb-bin
#   server_id   = 1
#   binlog_format = ROW
#   expire_logs_days = 7
```

```bash
sudo systemctl restart mysqld
mysql -e "SHOW VARIABLES LIKE 'log_bin';"        -- want ON
mysql -e "SHOW BINARY LOGS;"                       -- list current logs
mysql -e "SHOW MASTER STATUS;"                     -- current file + position
```

`ROW` format is the safest for PITR and replication (logs actual row changes,
not statements). `binlog` files live in the data dir and **must be backed up
alongside the dumps** — they are useless if lost.

## Base dump that records the coordinate

```bash
# MySQL 8.0.26+: --source-data ; older MySQL / MariaDB: --master-data
mysqldump --all-databases --single-transaction --source-data=2 \
          --routines --triggers --events > base.sql
```

`--source-data=2` writes a *commented* `CHANGE MASTER`/`CHANGE REPLICATION
SOURCE` line into the dump recording the exact binlog file + position at dump
time. `=1` writes it uncommented (for setting up a replica). Use `=2` for PITR
bookkeeping so the restore doesn't try to start replication.

## Recovery procedure

```bash
# 1. Find the coordinate the base dump started at:
grep -m1 'CHANGE MASTER\|CHANGE REPLICATION SOURCE' base.sql
#   -> MASTER_LOG_FILE='binlog.000007', MASTER_LOG_POS=4

# 2. Restore the base dump onto a clean instance:
mysql < base.sql

# 3. Replay binlogs from that position up to just before the disaster.
#    By time:
mysqlbinlog --start-position=4 \
            --stop-datetime="2026-06-15 14:29:59" \
            /var/lib/mysql/binlog.000007 /var/lib/mysql/binlog.000008 \
  | mysql

#    — or precisely by position (find it with --verbose first):
mysqlbinlog --start-position=4 --stop-position=98765 \
            /var/lib/mysql/binlog.000007 | mysql
```

Inspect events before replaying so you stop at the right spot:
```bash
mysqlbinlog --verbose --base64-output=DECODE-ROWS \
            /var/lib/mysql/binlog.000008 | less
```

## GTID note

If GTIDs are enabled (`gtid_mode=ON`, MySQL) replay by excluding the offending
transaction's GTID instead of by position. MariaDB uses its own GTID format.
For a single-server PITR the file+position method above is simplest.

## Operational rules

- Back up binlogs together with the dump; rotate them off the DB host.
- Never `RESET MASTER` / `PURGE BINARY LOGS` past a point you still need to
  recover to.
- Test the full restore-then-replay on a scratch instance before you depend on it.
