# MySQL backup lab baseline

Date: 2026-10-29 (UTC). Evidence was captured from the unmodified HEAD version
of `scripts/sk-mysql-backup.sh` before remediation. The script was confirmed
unchanged from HEAD.

## Lab boundary

- Source and restore target: `docker.io/library/mysql:8.4`, MySQL Community
  Server 8.4.13, separate Podman containers on one internal network.
- No host ports were published. No host database service or package was
  changed.
- The source contained only synthetic database `lab_app`, one witness row
  (`synthetic-lab-row-20261029`), one trigger and one stored procedure.
- The runner was the MySQL 8.4 image (Oracle Linux base). rclone v1.75.2 was
  copied from its official container image into the private temporary lab
  directory. The remote was the local `:local:` backend; no paid cloud was used.
- Generated database and GPG credentials remained under a mode-0700 temporary
  directory outside the repository. They are not retained as evidence.

## Baseline observations

1. With `umask 022`, the original script completed a real `mysqldump`, tar,
   AES256 GPG encryption, and rclone local upload in 2 seconds. The resulting
   encrypted file had mode 0644. The full redacted runner log is
   [`mysql-lab-baseline-success.log`](mysql-lab-baseline-success.log).
2. With an isolated fake `gpg` executable returning 42 after archive creation,
   the script returned 1 in 1 second but left the plaintext tar archive in the
   backup directory with mode 0644 (1,704,151 bytes). The script's final
   success message did not appear. The full redacted runner log is
   [`mysql-lab-baseline-gpg-failure.log`](mysql-lab-baseline-gpg-failure.log).
3. The source row, trigger, and routine were verified before the backup:
   witness count 1 and marker `synthetic-lab-row-20261029`; trigger count 1;
   routine count 1.

The controlled failure was synthetic and intentionally isolated. Its plaintext
archive was removed with the disposable lab directory after recording metadata;
no credentials or production data were involved.

## Baseline file fingerprint

20175fbc023bbdb777cce39c620878286864228745637167a405264507d4f6c2  scripts/sk-mysql-backup.sh

<!-- Author: Peter Bamuhigire <techguypeter.com> +256784464178 -->
