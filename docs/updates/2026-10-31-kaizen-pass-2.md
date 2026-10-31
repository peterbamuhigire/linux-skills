# Kaizen pass 2: what operators need to act on - 2026-10-31

## Change

Four defects found in the 29 October release are fixed in the repository. Two of them change
what an operator should check on hosts that were set up or backed up with the earlier
procedures. Full evidence: [pass-2 final report](../kaizen/2026-10-engine-kaizen-pass-2/05-final-report.md).

| Area | What changed | What to check on an existing host |
|---|---|---|
| SSH hardening drop-in | The provisioning, hardening, access-control and security-notes procedures now name the file `00-linux-skills-ssh.conf`. OpenSSH keeps the first value it reads across `/etc/ssh/sshd_config.d/*.conf` in lexical order, so the old name `99-hardening.conf` lost to `50-cloud-init.conf` and left `PasswordAuthentication yes` in force (shown with `sshd -T` on OpenSSH 10.2). | `sudo sshd -T \| grep -Ei 'passwordauthentication\|permitrootlogin'`. If a value is not what you set, find the earlier definition with `sudo grep -rniE '^[[:space:]]*passwordauthentication' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/`. Rename your file so it sorts first, run `sudo sshd -t`, reload, and verify a key login from a second terminal before closing the first. |
| `sk-pg-backup` | Writes every file mode 0600 through a private staging directory, checks each dump with `pg_restore --list`, renames it into place only if it passes, and removes staging on every exit. Retention is validated, touches only `<database>_<timestamp>.dump` and `globals_<timestamp>.sql`, and a failed prune now fails the run. Needs `pg_restore`. Dumps are still not encrypted. | Files written by earlier versions keep mode 0644 and the globals file holds role password hashes: `ls -l /var/backups/postgresql`, then `sudo chmod 600` on the old `*.dump` and `globals_*.sql` files you intend to keep. |
| Backup configuration files | `/etc/linux-skills/mysql-backup.conf` and `pg-backup.conf` are sourced as root. Both scripts now refuse a file that is a symlink, not owned by root (or the caller), or writable by group or others, or sits in a directory that is, and exit 3. `sk-pg-backup` now lets command-line flags override the file. | `ls -ld /etc/linux-skills /etc/linux-skills/*.conf`; fix ownership and mode rather than loosening the check. |
| Audit log for non-root runs | When `/var/log/linux-skills` does not exist, a non-root run no longer writes to a predictable directory in `/tmp`; it uses a private `0700` directory under the temporary base or skips the audit line with one warning. | None unless you read audit lines from `/tmp/linux-skills-<user>`. |

## Installed copies can be older than this checkout

On the validation workstation `/usr/local/bin/sk-mysql-backup` reports version 0.3.0 and
`/usr/local/lib/linux-skills/common.sh` dates from 15 June and lacks the temporary-directory
validation. The 29 October repairs and these fixes only reach a host when its scripts are
reinstalled. `install-skills-bin --list` prints `yes` under INSTALLED? even when the installed
file differs from the repository copy, and `install-skills-bin core` refuses to replace a
differing script without `--force`. Review the difference, then:

```bash
sudo install-skills-bin core --dry-run
sudo install-skills-bin core --force
```

Both new backup scripts check for the helper they need and stop with exit 5 and this advice if the
installed library is older. This pass did not run the installer here (no `sudo`).

## Limits

- Fixture evidence only: stubbed PostgreSQL tools, a throwaway `sshd -T` configuration tree, and a
  Fedora 44 host for the dnf5 observation. No PostgreSQL restore, no enterprise RHEL host and no
  ACME renewal was run: all `NOT_ASSESSED`.
- Debian stable is 13 (point release 13.7 on 2026-09-12) and PostgreSQL 14 reaches its final release on
  2026-11-12: [currency record](../kaizen/2026-10-engine-kaizen-pass-2/currency.md).

*Author: Peter Bamuhigire (techguypeter.com).*
