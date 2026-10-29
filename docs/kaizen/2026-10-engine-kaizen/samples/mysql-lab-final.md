# MySQL backup/restore lab result

Date: 2026-10-29 UTC. Author: Peter Bamuhigire <techguypeter.com>
(+256784464178).

## Scope and environment

- Source and restore target were separate `docker.io/library/mysql:8.4`
  containers running MySQL Community Server 8.4.13. The runner used the same
  image (Oracle Linux base), `gpg`, `tar`, and the MySQL 8.4 client tools.
- The containers shared a Podman `--internal` network. No host database ports
  were published. The only test schema was synthetic `lab_app`, with one
  witness row, one trigger, and one stored procedure.
- rclone v1.75.2 wrote to the local `:local:` backend. No paid cloud or
  external model call was used. Generated MySQL/GPG credentials were held in a
  private temporary directory outside the repository and are not retained.
- Repository was mounted read-only in script runner containers; only the
  temporary lab directory was mounted writable. No host package or service was
  changed.
- Debian/Fedora-specific runner package behavior was not tested; the official
  MySQL image's Oracle Linux-based client/server stack was used for this lab.
  Production data, external cloud storage, and real retention expiration were
  not assessed.

## Observed results

| Operation | UTC interval | Elapsed | Result |
|---|---|---:|---|
| Final script backup + GPG + local rclone copy | 03:44:53–03:44:55 | 2,012 ms | Exit 0; one local and remote encrypted artifact; local mode 0600 |
| Repeated backup | 03:44:57–03:44:59 | 2,027 ms | Exit 0; two distinct local and remote artifacts |
| Clean target restore, decrypt/extract/import and reconciliation | 03:44:59–03:45:00 | 803 ms | Exit 0; source and target versions both 8.4.13 |
| Injected GPG failure | 03:45:08–03:45:10 | 1,934 ms | Exit 1; no plaintext archive, partial encrypted file, or staging directory remained |
| Injected rclone remote-retention failure | 03:45:10–03:45:11 | 1,785 ms | Exit 1; success message omitted; completed encrypted local artifact retained |
| Dry-run | 03:41:59–03:41:59 | 303 ms | Exit 0; intended steps shown and backup destination remained absent |

Reconciliation ran on both source and target:

```sql
SELECT COUNT(*), MIN(marker) FROM lab_app.witness;
SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema='lab_app';
SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema='lab_app';
```

Both returned `1 / synthetic-lab-row-20261029`, trigger count `1`, routine
count `1`. The encrypted file used for restore had SHA-256
`bf6fb0fe4b7c8d3ccc6c966f9e7577437ebe080d2910e4124e6f20ce9ba6cb16`, mode
`0600`, and size 1,704,272 bytes. The controlled remote-retention failure
happened after a successful upload. The successful-run local and remote
destinations held two artifacts each; the injected failure left one additional
encrypted file in its separate local failure directory and uploaded a third
file to the shared remote. That is expected recovery state, not a successful
retention result.

Full runner output:

- [Final backup](mysql-lab-final-success.log)
- [Repeated backup](mysql-lab-final-repeat.log)
- [Clean restore and verification](mysql-lab-final-restore.log)
- [Injected GPG failure](mysql-lab-final-gpg-failure.log)
- [Injected retention failure](mysql-lab-final-retention-failure.log)
- [Dry-run](mysql-lab-final-dry-run.log)
- [Unmodified baseline observations](mysql-lab-baseline.md)

The collected integration test passed using disposable Podman containers:

```text
LINUX_SKILLS_MYSQL_BACKUP_LAB=1 /tmp/linux-kaizen-checks/venv/bin/python -m pytest -q tests/test_mysql_backup.py
1 passed in 40.70s
```

Final `scripts/sk-mysql-backup.sh` SHA-256: `79dd3307d7149a014a246876063d61fed240e9aa89b8a2cfc3418e3261ae968f`.

<!-- Author: Peter Bamuhigire <techguypeter.com> +256784464178 -->

Post-lab lint change: only ShellCheck explanatory comments were added to the backup script; behaviour is unchanged. Release script SHA-256: `fbb274fbd0bd90d5bab5033391a5459fddd500eda822b1b0efbd48e65f1eaf4c`. The earlier hash above identifies the executed lab source.
