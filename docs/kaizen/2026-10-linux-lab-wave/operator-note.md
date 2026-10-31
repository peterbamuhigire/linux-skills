# Operator note — Linux lab wave, 31 October 2026

What changed that matters on a host, and the read-only checks that tell you whether a host needs attention.
Nothing here was applied to the workstation or to any server by the wave.

## Debian hosts: check that automatic security updates really match

If a Debian host was set up from the earlier "Unattended security upgrades" text (it told you to allow
`"${distro_id}:${distro_codename}-security"`), check it:

```bash
sudo unattended-upgrade --dry-run --debug 2>&1 | grep -E 'Allowed origins|Packages that will be upgraded|No packages found'
apt-get -s dist-upgrade | grep '^Inst' | grep -i security
```

The first command must show `label=Debian-Security`. If the second lists packages and the first says
`No packages found that can be upgraded unattended`, the host is not patching itself. The procedure in
`01-provisioning-and-bootstrap/linux-server-provisioning/references/provisioning-steps.md` (section 5) now has the
Debian form. The earlier text was inert only where the shipped stanza had been removed or replaced.

## RHEL-family hosts: reload SSH as `sshd`

`systemctl reload ssh` does not exist there (exit 5). Use `sudo sshd -t && sudo systemctl reload sshd`, always with
the `sshd -t &&` guard: the packaged RHEL unit has no syntax check of its own, and in the lab a bad drop-in followed by
a plain reload stopped the daemon.

## MySQL backup account

`PROCESS` is optional. Without it `mysqldump` 8.4 prints an access-denied line about tablespaces on standard error,
exits 0 and dumps every schema; only `CREATE TABLESPACE` statements for general tablespaces are left out. Decision
for you in `06-next-cycle.md`: whether `sk-mysql-backup` should pass `--no-tablespaces`.

## Installed scripts are older than this checkout

Changed scripts in this wave: `sk-pg-backup` (client calls run from `/`, usage wording) and `scripts/lib/common.sh`
(the failure banner after `die`). 24 other scripts gained a comment-only ShellCheck directive. To see what an installed
copy lacks:

```bash
diff /usr/local/lib/linux-skills/common.sh ~/.claude/skills/linux-skills/scripts/lib/common.sh
install-skills-bin --list
```

Updating the installed copies is `sudo install-skills-bin core --force` after you have read the diff. The wave did not
run it.

## Re-running the labs

```bash
cd ~/.claude/skills/linux-skills
LINUX_SKILLS_LAB=1 python3 -m pytest -rP tests/test_distro_labs.py                                  # Debian 12 and Fedora 44
LINUX_SKILLS_MYSQL_BACKUP_LAB=1 LINUX_SKILLS_LAB_PREFIX=lskw- python3 -m pytest tests/test_mysql_backup.py
podman ps --all --format '{{.Names}}' | grep '^lskw-'    # must print nothing afterwards
```

They need rootless Podman and the local images `debian:bookworm`, `fedora:44`, `mysql:8.4` and `rclone`; they pull
nothing, publish no ports and mount no host path. Use `pytest` where it is installed.

Author: Peter Bamuhigire, techguypeter.com, +256784464178.
