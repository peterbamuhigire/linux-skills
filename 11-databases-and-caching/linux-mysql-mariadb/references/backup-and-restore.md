# MySQL backup and restore verification

Use this procedure for a logical backup made by `sk-mysql-backup`. A successful
dump or upload alone does not prove that the backup can restore.

## Configure and run

The script reads `MYSQL_CNF`, `BACKUP_DIR`, `GPG_KEY_FILE`, and retention
settings from `/etc/linux-skills/mysql-backup.conf` or the environment. The
client credential file and GPG passphrase file must be regular files with mode
`0600`. Under `--yes`, provide an rclone remote explicitly or in the config.

```bash
sudo install-skills-bin linux-mysql-mariadb
sudo sk-mysql-backup --dry-run --mysql-cnf /root/.mysql-backup.cnf \
  --backup-dir /var/backups/mysql --gpg-key-file /root/.backup-encryption-key \
  --rclone-remote backup:host/mysql
sudo sk-mysql-backup --yes --mysql-cnf /root/.mysql-backup.cnf \
  --backup-dir /var/backups/mysql --gpg-key-file /root/.backup-encryption-key \
  --rclone-remote backup:host/mysql
```

The script uses a private working directory, creates files under umask `077`,
and retains completed encrypted `.gpg` files locally after upload. It removes
the plaintext working archive after encryption. If encryption fails, it
removes the plaintext archive and any partial encrypted output. A failed upload
or remote retention step returns nonzero; a completed encrypted local copy is
left available for retry. Local and remote retention apply only to the
script's `mysql-backup_*.tar.gz.gpg` files.

## Backup account

The credentials file named by `MYSQL_CNF` should belong to a dedicated account, not
`root`. The script runs `mysqldump --single-transaction --routines --triggers --events`
once per schema and once for `--all-databases`. The MySQL 8.4 `mysqldump` manual page
(read 2026-10-31) says that command set needs:

| Need | Privilege |
|---|---|
| Rows of every dumped table | `SELECT`; `--routines` requires the **global** `SELECT` |
| Views, triggers, events | `SHOW VIEW`, `TRIGGER`, `EVENT` |
| Tablespace metadata | `PROCESS`, unless `--no-tablespaces` is passed (the script does not pass it) |
| Consistent snapshot with GTIDs | `RELOAD` or `FLUSH_TABLES` with `--single-transaction`, when `gtid_mode=ON` and `gtid_purged=ON` or `AUTO` |
| Table locks | not needed: `--single-transaction` replaces `LOCK TABLES` |

```sql
CREATE USER 'sk_backup'@'localhost' IDENTIFIED BY '<generated, kept only in the 0600 option file>';
GRANT SELECT, SHOW VIEW, TRIGGER, EVENT, PROCESS, RELOAD ON *.* TO 'sk_backup'@'localhost';
```

Treat that credential like the dump itself: global `SELECT` reads the `mysql` schema,
and `PROCESS` shows every session's statements. Two traps follow from narrowing the
grants. The script lists schemas from `information_schema.schemata`, and MySQL shows a
user only the rows for objects it has some privilege on, so a schema the account cannot
see is left out of the backup and the run still reports success. Compare the dumped
schema list with `SHOW DATABASES` run by an administrator before trusting a narrower
account. A missing privilege on a schema the account can see makes `mysqldump` fail, and the
script then stops with `mysqldump failed` (exit 1).

Status: the privilege list comes from the manual page, not from a server run in this
review; the example statements were not executed. MariaDB ships `mariadb-dump`
and its grants were not assessed. Sources: MySQL 8.4
reference manual, `mysqldump` and INFORMATION_SCHEMA introduction pages, read
2026-10-31; review by 2026-11-30.

## Verify a backup

Record the source engine/version, backup start and end times, encrypted file
name, mode, size, and SHA-256 digest. Keep this evidence free of credentials and
database values that are not approved for the change record.

Restore into a separate, isolated MySQL instance of a compatible version. Do
not overwrite the source instance. Decrypt and extract the archive in a private
directory, then restore the per-database dump to the isolated target:

```bash
umask 077
install -d -m 0700 /var/tmp/mysql-restore-check
gpg --batch --decrypt --passphrase-file /root/.backup-encryption-key \
  --output /var/tmp/mysql-restore-check/backup.tar.gz \
  /var/backups/mysql/mysql-backup_<timestamp>.tar.gz.gpg
tar -xzf /var/tmp/mysql-restore-check/backup.tar.gz \
  -C /var/tmp/mysql-restore-check
```

Use the target's protected client option file and restore the appropriate
per-database SQL file:

```bash
mysql --defaults-file=/root/.mysql-restore-target.cnf \
  < /var/tmp/mysql-restore-check/dump_<timestamp>/database_<index>_<database>.sql
```

Then compare schema/object counts and representative row counts or approved
non-sensitive checksums with the source. Verify routines,
triggers, and events required by the application. Record the target engine
version, queries and results, elapsed restore time, and health checks. If the
restore or reconciliation fails, mark recovery unproven and preserve the last
known-good backup.

The automated disposable lab is opt-in:

```bash
LINUX_SKILLS_MYSQL_BACKUP_LAB=1 pytest -q tests/test_mysql_backup.py
```

It needs pre-pulled Podman images `docker.io/library/mysql:8.4` and
`docker.io/rclone/rclone`; it publishes no database ports and uses only a
synthetic database and rclone's local backend.

<!-- Author: Peter Bamuhigire <techguypeter.com> +256784464178 -->
