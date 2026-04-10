# Permissions Reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

The complete reference for Linux file permissions on Ubuntu/Debian
servers: the classical Unix permission bits, the special bits (SUID,
SGID, sticky), `umask`, POSIX ACLs, extended attributes, the canonical
permission tables for web roots, `/etc`, credentials and SSH
directories, and the command patterns to detect anomalies and repair
them. Every mode is written as both symbolic and octal so you can match
what `ls -l` shows and what `chmod` expects.

## Table of contents

- [The permission bits](#the-permission-bits)
- [Numeric modes — the short table](#numeric-modes--the-short-table)
- [Special bits: SUID, SGID, sticky](#special-bits-suid-sgid-sticky)
- [umask — defaults for new files](#umask--defaults-for-new-files)
- [POSIX ACLs](#posix-acls)
- [Extended attributes: lsattr and chattr](#extended-attributes-lsattr-and-chattr)
- [Canonical permission tables](#canonical-permission-tables)
- [Detecting anomalies](#detecting-anomalies)
- [Repair patterns](#repair-patterns)
- [Sources](#sources)

## The permission bits

Every file and directory on Linux carries three permission triplets plus
three special bits:

```
    -   rwx rwx rwx
    ^    |   |   |
    |    |   |   +-- other (world) — anyone not the owner and not in the group
    |    |   +------ group
    |    +---------- owner (user)
    +--------------- file type: - file, d directory, l symlink, b block, c char, p fifo, s socket
```

Within each triplet:

| Symbol | On a file                                 | On a directory                                 |
|--------|-------------------------------------------|------------------------------------------------|
| `r`    | Read file contents                        | List directory entries (`ls`)                  |
| `w`    | Modify or truncate file contents          | Create, rename, delete files in the directory  |
| `x`    | Execute (requires `r` too for scripts)    | Traverse the directory (`cd`, open a child)    |

**Critical rule:** `w` on a directory lets the user delete any file in it
regardless of who owns the file. That is why `/tmp` has the sticky bit.

## Numeric modes — the short table

| Octal | Symbolic   | When to use                              |
|-------|------------|------------------------------------------|
| 700   | `rwx------` | Private dirs (`~/.ssh`), sensitive scripts |
| 600   | `rw-------` | Private files (keys, creds, shadow-like) |
| 644   | `rw-r--r--` | Normal readable files (HTML, configs)    |
| 640   | `rw-r-----` | Group-readable configs (`/etc/shadow`, nginx configs with secrets) |
| 755   | `rwxr-xr-x` | Normal dirs, user-installed binaries     |
| 750   | `rwxr-x---` | Private user home dir (Ubuntu default is 755) |
| 775   | `rwxrwxr-x` | Group-writable shared directory          |
| 1777  | `rwxrwxrwt` | `/tmp` — world-writable with sticky      |
| 2755  | `rwxr-sr-x` | SGID directory (new files inherit group) |
| 4755  | `rwsr-xr-x` | SUID binary (runs as owner)              |
| 440   | `r--r-----` | `/etc/sudoers` — root read-only          |

## Special bits: SUID, SGID, sticky

### SUID (set user ID on execution) — `4xxx`

When set on an executable file, the process runs with the **effective
UID of the file owner**, not the caller. The classical example is
`/usr/bin/passwd` — a regular user invokes it but it needs to write to
`/etc/shadow` which only root can touch, so it's owned by root with the
SUID bit.

```bash
ls -l /usr/bin/passwd       # -rwsr-xr-x 1 root root ...
                            #    ^ the s in place of the owner x
chmod u+s /path/to/bin      # set SUID (symbolic)
chmod 4755 /path/to/bin     # set SUID (octal)
chmod u-s /path/to/bin      # remove SUID
```

**SUID is a surveillance target.** Every SUID binary on the system is an
LPE candidate. Know your baseline; flag anything new.

### SGID (set group ID on execution) — `2xxx`

Same idea for group. More common on directories, where it has a
different meaning: new files created inside an SGID directory inherit
the directory's group, not the creator's primary group. Useful for
shared team directories.

```bash
ls -l /var/local/shared     # drwxrwsr-x ...
                            #        ^ the s in place of group x
chmod g+s /var/local/shared
chmod 2775 /var/local/shared
```

### Sticky bit — `1xxx`

On a directory, the sticky bit means "only the owner of a file (or root)
can delete or rename it, even if the directory is world-writable". That
is why `/tmp` is mode `1777` — everyone can write files there, but
nobody can delete anyone else's.

```bash
ls -ld /tmp                 # drwxrwxrwt 10 root root
                            #          ^ the t
chmod +t /tmp
chmod 1777 /tmp
```

### Reading the octal

The four-digit octal form is `<special><owner><group><other>`:

- special = sum of SUID(4) + SGID(2) + sticky(1)
- owner/group/other = sum of r(4) + w(2) + x(1)

So `4755` = SUID, `rwx`, `r-x`, `r-x`. And `1777` = sticky, `rwx`, `rwx`,
`rwx`.

## umask — defaults for new files

`umask` is the set of bits **removed** from the mode of new files and
directories as they're created. Files start from `666`; directories
start from `777`.

| Umask | New file mode | New dir mode | Notes                            |
|-------|---------------|--------------|----------------------------------|
| 022   | 644           | 755          | Distro default. World-readable.  |
| 027   | 640           | 750          | Tighter — world can't read.      |
| 077   | 600           | 700          | Private-only (root home default).|

```bash
umask                          # show current
umask 027                      # set for this shell
grep umask /etc/login.defs     # system-wide default (UMASK 022 by default)
grep umask /etc/profile /etc/bash.bashrc
```

To change the server-wide umask for interactive users:

```bash
sudo sed -i 's/^UMASK.*/UMASK 027/' /etc/login.defs
# and for non-login shells:
echo 'umask 027' | sudo tee -a /etc/bash.bashrc
```

Per-user overrides go in `~/.bashrc` or `~/.profile`.

## POSIX ACLs

When the classic owner/group/other model is too blunt — e.g. grant one
extra user write access without adding them to the file's group — use
POSIX ACLs. Requires the filesystem to be mounted with `acl` (Ubuntu's
ext4/xfs defaults include it).

```bash
# View ACL
getfacl /var/www/html

# Grant user bob rw on a file
setfacl -m u:bob:rw /var/www/html/config.php

# Grant group devs rx on a directory and inherit for new files
setfacl -m g:devs:rx /srv/app
setfacl -d -m g:devs:rx /srv/app   # default ACL for new children

# Remove an entry
setfacl -x u:bob /var/www/html/config.php

# Remove all ACL entries (back to pure octal mode)
setfacl -b /var/www/html/config.php
```

`ls -l` shows a trailing `+` on files that have ACLs beyond the basic
mode: `-rw-r--r--+  1 root root ...`. When auditing, `find ... -lname '+'`
doesn't work — use `getfacl -R /path | grep -v '^#'` to dump all ACLs.

## Extended attributes: lsattr and chattr

Ext filesystems support flags beyond the permission bits, exposed via
`chattr` and `lsattr`. The two you actually need:

### `+i` — immutable

A file with `+i` cannot be modified, renamed, deleted, or even touched
— **including by root** — until the flag is cleared. Perfect for
critical files that should never change without a maintenance window:

```bash
sudo chattr +i /etc/resolv.conf
sudo chattr +i /etc/ssh/sshd_config       # during a lockdown

# View
lsattr /etc/resolv.conf
# ----i---------e------- /etc/resolv.conf

# Remove before editing
sudo chattr -i /etc/resolv.conf
```

Beware: systemd-resolved and DHCP clients will fight `+i` on
`/etc/resolv.conf`. Only use it on files no daemon will rewrite.

### `+a` — append-only

The file can be opened for writing only in append mode. Useful for logs
that you want to allow rotation to extend but not tampering:

```bash
sudo chattr +a /var/log/auth.log
echo "test" >> /var/log/auth.log       # works
echo "test" >  /var/log/auth.log       # fails with "Operation not permitted"
sudo chattr -a /var/log/auth.log       # to allow rotation
```

### Dumping attributes during an audit

```bash
lsattr /etc/passwd /etc/shadow /etc/sudoers /etc/resolv.conf
sudo find /etc -maxdepth 2 -type f -exec lsattr -d {} + 2>/dev/null | \
    grep -E '[ia]'
```

Anything unexpected with `i` or `a` during an incident response is
worth a closer look — attackers sometimes set `+i` on their backdoor to
stop you from removing it easily.

## Canonical permission tables

### System critical files

| Path                          | Mode | Owner         | Notes                        |
|-------------------------------|------|---------------|------------------------------|
| `/etc/passwd`                 | 644  | root:root     | Must be world-readable       |
| `/etc/group`                  | 644  | root:root     | Must be world-readable       |
| `/etc/shadow`                 | 640  | root:shadow   | Never world-readable         |
| `/etc/gshadow`                | 640  | root:shadow   | Never world-readable         |
| `/etc/sudoers`                | 440  | root:root     | `visudo` enforces this       |
| `/etc/sudoers.d/*`            | 440  | root:root     | Same                         |
| `/etc/ssh/sshd_config`        | 600  | root:root     | Keys + auth config           |
| `/etc/ssh/ssh_host_*_key`     | 600  | root:root     | Host private keys            |
| `/etc/ssh/ssh_host_*_key.pub` | 644  | root:root     | Host public keys             |
| `/etc/cron.d/`                | 755  | root:root     | Dir                          |
| `/etc/crontab`                | 644  | root:root     | System cron                  |
| `/boot/grub/grub.cfg`         | 600  | root:root     | Hide boot params             |

### Web root (`/var/www/html`)

| Path                          | Mode | Owner                 |
|-------------------------------|------|-----------------------|
| `/var/www`                    | 755  | root:root             |
| `/var/www/html/` (dir)        | 755  | www-data:www-data     |
| `/var/www/html/` (files)      | 644  | www-data:www-data     |
| Deploy-only config files      | 640  | deploy:www-data       |
| Upload dirs                   | 775  | www-data:www-data     |
| `.env`, `config.php`, keys    | 640  | deploy:www-data       |

**Files inside `/var/www/html` must not have world-write.** Enforce:

```bash
sudo find /var/www -type f -perm -0002 -exec chmod o-w {} \;
sudo find /var/www -type d -perm -0002 -exec chmod o-w {} \;
```

### SSH directories

| Path                                  | Mode | Owner      |
|---------------------------------------|------|------------|
| `~/.ssh/`                             | 700  | user:user  |
| `~/.ssh/authorized_keys`              | 600  | user:user  |
| `~/.ssh/config`                       | 600  | user:user  |
| `~/.ssh/known_hosts`                  | 644  | user:user  |
| `~/.ssh/id_*` (private keys)          | 600  | user:user  |
| `~/.ssh/id_*.pub`                     | 644  | user:user  |

sshd will refuse to honor keys if `~/.ssh` or `authorized_keys` are
group- or world-writable — this is the #1 "why isn't my key working"
cause on a fresh server.

### Credential files

| Path                            | Mode | Owner      |
|---------------------------------|------|------------|
| `~/.mysql-backup.cnf`           | 600  | user:user  |
| `~/.pgpass`                     | 600  | user:user  |
| `~/.netrc`                      | 600  | user:user  |
| `~/.backup-encryption-key`      | 600  | user:user  |
| `~/.config/rclone/rclone.conf`  | 600  | user:user  |
| `~/.aws/credentials`            | 600  | user:user  |
| `~/.aws/config`                 | 600  | user:user  |
| `/etc/mysql/debian.cnf`         | 600  | root:root  |

Client tools like `mysql`, `psql`, `curl`, `rclone`, `awscli` refuse to
use credential files that are not 600 — they will print a warning and
fall back to interactive auth.

### Log files

| Path                          | Mode | Owner              |
|-------------------------------|------|--------------------|
| `/var/log/` (dir)             | 755  | root:root          |
| `/var/log/auth.log`           | 640  | syslog:adm         |
| `/var/log/syslog`             | 640  | syslog:adm         |
| `/var/log/nginx/` (dir)       | 755  | root:adm           |
| `/var/log/nginx/access.log`   | 640  | www-data:adm       |
| `/var/log/nginx/error.log`    | 640  | www-data:adm       |
| `/var/log/mysql/error.log`    | 640  | mysql:adm          |

Users in the `adm` group can read system logs without being root.

## Detecting anomalies

### World-writable files and directories

```bash
# Files with world-write under /var/www
sudo find /var/www -type f -perm -0002

# Directories world-writable without sticky bit (red flag)
sudo find / -xdev -type d -perm -0002 ! -perm -1000 \
    -not -path '/proc/*' -not -path '/sys/*' -not -path '/dev/*' 2>/dev/null
```

### SUID/SGID hunt

```bash
# List all SUID/SGID binaries on local filesystems
sudo find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null

# Minus the expected distro baseline
sudo find / -xdev -perm /6000 -type f 2>/dev/null | grep -vE \
    '/(sudo|passwd|su|mount|umount|ping|ping6|chfn|chsh|newgrp|gpasswd|expiry|\
chage|pkexec|ssh-agent|dbus-daemon-launch-helper|pam_timestamp_check|\
unix_chkpwd|fusermount3|utempter|mtr-packet|suexec|at|crontab)$'
```

Anything in `/tmp`, `/var/tmp`, `/dev/shm`, or a user's `$HOME` is
almost certainly malicious.

Confirm each unknown binary belongs to a package before panicking:

```bash
dpkg -S /path/to/suspect            # which package
debsums -c /path/to/suspect 2>&1    # checksum still matches distro?
```

### Orphaned files

```bash
sudo find /var/www /home /etc /opt -xdev \( -nouser -o -nogroup \) 2>/dev/null
```

Usually the leftovers of a removed user. Either `chown` them to a real
account or delete them.

### Files writable by www-data outside the web root

```bash
sudo find / -xdev -user www-data -writable 2>/dev/null | grep -v '^/var/www'
```

### Credential file mode check

```bash
for f in ~/.mysql-backup.cnf ~/.pgpass ~/.netrc ~/.backup-encryption-key \
         ~/.config/rclone/rclone.conf ~/.aws/credentials; do
    [ -f "$f" ] && printf '%s %s\n' "$(stat -c '%a' "$f")" "$f"
done
```

Any line not starting with `600` is a finding.

## Repair patterns

### Reset a compromised web root

```bash
cd /var/www/html
sudo chown -R www-data:www-data .
sudo find . -type d -exec chmod 755 {} \;
sudo find . -type f -exec chmod 644 {} \;
# Keep deployer-only config 640
sudo find . -maxdepth 2 -name 'config*.php' -o -name '.env' | \
    sudo xargs -r chmod 640
```

### Reset system critical permissions

```bash
sudo chown root:root /etc/passwd /etc/group
sudo chown root:shadow /etc/shadow /etc/gshadow
sudo chmod 644 /etc/passwd /etc/group
sudo chmod 640 /etc/shadow /etc/gshadow
sudo chmod 440 /etc/sudoers
sudo chmod 600 /etc/ssh/sshd_config
sudo chmod 600 /etc/ssh/ssh_host_*_key
sudo chmod 644 /etc/ssh/ssh_host_*_key.pub
```

### Reset a user's ~/.ssh after permission trouble

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys ~/.ssh/id_* ~/.ssh/config 2>/dev/null
chmod 644 ~/.ssh/id_*.pub ~/.ssh/known_hosts 2>/dev/null
chown -R "$USER:$USER" ~/.ssh
```

### Strip unexpected SUID

```bash
sudo chmod u-s /path/to/suspect-binary
# And remove if confirmed malicious:
sudo rm -f /path/to/suspect-binary
```

### Fix every "client tool refuses credential file" warning at once

```bash
find ~ -maxdepth 3 -type f \( -name '.pgpass' -o -name '.netrc' -o \
    -name '.mysql-backup.cnf' -o -name '.backup-encryption-key' \) \
    -exec chmod 600 {} +
```

## Optional fast path

Running `sudo install-skills-bin linux-access-control` installs
`sk-user-audit`, `sk-ssh-key-audit`, `sk-new-sudoer`, and
`sk-user-suspend`, which wrap the commands above. The manual patterns in
this file remain the source of truth.

## Sources

- *Mastering Linux Security and Hardening*, Donald A. Tevault, 3rd
  Edition, Packt — Chapter 8 "Mastering Discretionary Access Control"
  (SUID/SGID on regular files, security implications, securing system
  configuration files) and Chapter 9 "Access Control Lists and Shared
  Directory Management".
- *Practical Linux Security Cookbook*, Tajinder Kalsi, Packt — recipes
  for SUID/SGID scans, umask, ACLs, and file attribute hardening.
- *Ubuntu Server Guide*, Canonical — "Security" chapter: file permissions,
  users and groups, console security.
- Manual pages: `chmod(1)`, `chown(1)`, `umask(2)`, `setfacl(1)`,
  `getfacl(1)`, `chattr(1)`, `lsattr(1)`, `find(1)`.
