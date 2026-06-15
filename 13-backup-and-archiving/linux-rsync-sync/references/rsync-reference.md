# rsync reference

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

Complete `rsync` reference for offsite and incremental backups. Every command
works on a stock Debian/Ubuntu or RHEL-family install (`apt install rsync` /
`dnf install rsync`). Companion to the skill body; the incremental
`--link-dest` rotation strategy lives in
[`incremental-snapshots.md`](incremental-snapshots.md).

## Table of contents

1. The trailing-slash rule
2. Archive mode and what `-a` expands to
3. Change detection: mtime+size vs `--checksum`
4. The itemized change list (`-i`)
5. `--delete` modes
6. Include/exclude filter rules
7. Bandwidth, compression, and link tuning
8. rsync over SSH
9. Restartable transfers
10. Common recipes
11. Sources

---

## 1. The trailing-slash rule

This is the single most common rsync mistake.

```bash
rsync -a src/  dst/     # copy the CONTENTS of src into dst   → dst/file
rsync -a src   dst/     # copy the DIRECTORY src into dst     → dst/src/file
```

A trailing slash on the **source** means "the contents of". On the
**destination** it has no effect. When in doubt, `--dry-run` and read the paths.

---

## 2. Archive mode and what `-a` expands to

`-a` (archive) is shorthand for `-rlptgoD`:

| Flag | Meaning |
|---|---|
| `-r` | recurse into directories |
| `-l` | copy symlinks as symlinks |
| `-p` | preserve permissions |
| `-t` | preserve modification times (critical — lets the next run skip unchanged files) |
| `-g` | preserve group |
| `-o` | preserve owner (needs root on the target) |
| `-D` | preserve device and special files |

`-a` does **not** include `-A` (ACLs), `-X` (xattrs), `-H` (hard links), or
`-S` (sparse). Add them when needed:

```bash
rsync -aAXH /src/ /dst/    # + ACLs + xattrs + preserve hard-link structure
```

On a RHEL target with SELinux, `-X` carries the `security.selinux` xattr only
when source and target label identically; otherwise `restorecon -R /dst` after.

---

## 3. Change detection

By default rsync transfers a file only if **size or mtime differ**. This is
fast and correct for almost all backups.

```bash
rsync -a  src/ dst/        # default: quick check (size + mtime)
rsync -ac src/ dst/        # --checksum: full per-file checksum (slow, thorough)
rsync -a --size-only src/ dst/   # ignore mtime; only size (use rarely)
```

Use `--checksum` for integrity audits or when mtimes are unreliable (restored
trees, clock skew). A post-backup audit:

```bash
rsync -avnc src/ dst/      # dry-run + checksum: any output = drift detected
```

---

## 4. The itemized change list (`-i`)

`-i` prints a YXcstpoguax flag string per file. The first two chars are the
ones you read most:

| Token | Meaning |
|---|---|
| `>f+++++++` | new file being received |
| `>f.st....` | existing file, size+time changed |
| `cd+++++++` | new directory created |
| `*deleting` | file removed (with `--delete`) |
| `.f...p...` | only permissions changed |

```bash
rsync -ain --delete src/ dst/    # itemized dry-run of a mirror
```

---

## 5. `--delete` modes

`--delete` removes destination files that no longer exist in the source. Always
dry-run first.

| Flag | Behaviour |
|---|---|
| `--delete` | delete during transfer (default timing) |
| `--delete-before` | delete before transferring (frees space first) |
| `--delete-after` | delete after transferring (safest ordering) |
| `--delete-excluded` | also delete files the filter excludes |
| `--backup --backup-dir=DIR` | move deleted/replaced files to DIR instead |

```bash
# Safe mirror that keeps a dated trash of anything removed:
rsync -a --delete --backup --backup-dir=/mnt/backup/trash-$(date +%F) src/ dst/
```

---

## 6. Include/exclude filter rules

```bash
rsync -a --exclude='*.log' --exclude='/cache/' src/ dst/
rsync -a --exclude-from=/etc/backup-excludes.txt src/ dst/
rsync -a --include='*/' --include='*.conf' --exclude='*' src/ dst/  # only .conf
```

Rules:

- A leading `/` anchors to the transfer root; without it, the pattern matches at
  any depth.
- A trailing `/` matches directories only.
- `--include` must come **before** the broad `--exclude='*'` that follows it,
  and you need `--include='*/'` to descend into subdirs.

---

## 7. Bandwidth, compression, and link tuning

```bash
rsync -a --bwlimit=5000 src/ host:dst/     # cap ~5 MB/s (KB/s default; 5M ok)
rsync -az src/ host:dst/                    # -z compress in transit
rsync -a --whole-file src/ dst/             # skip delta algo on fast LAN/local
rsync -a --inplace src/ dst/                # write in place (good for big VM imgs)
```

- `--bwlimit` throttles so a backup never starves production traffic.
- `-z` helps on slow links with compressible data; skip it for already-compressed
  data (images, video, .gz) or fast LANs where CPU is the bottleneck.
- `--whole-file` disables the rolling-checksum delta transfer (it is a net win
  on local copies where there is no network to save).

[GROUNDING-GAP: `--bwlimit` units/leaky-bucket and `--inplace`/`--whole-file`
interactions are from upstream rsync(1) man page; deepen with UNIX & Linux
System Administration Handbook.]

---

## 8. rsync over SSH

```bash
rsync -a -e ssh src/ user@host:dst/                       # default transport
rsync -a -e 'ssh -p 2222 -i ~/.ssh/backup_ed25519' src/ user@host:dst/
rsync -a user@host:src/ /local/dst/                       # pull
```

For unattended backups use a dedicated key with no passphrase, locked down on
the server side with a `command=` restriction in `authorized_keys`. SSH key
setup is grounded in the RHCSA flow (`ssh-keygen`, `ssh-copy-id`).

---

## 9. Restartable transfers

```bash
rsync -a --partial --append-verify --progress bigfile host:dst/
rsync -aP src/ host:dst/                  # -P = --partial --progress
```

- `--partial` keeps a partially transferred file so a re-run resumes it.
- `--append-verify` resumes by appending, then checksums the whole result.
- `--partial-dir=.rsync-partial` keeps partials in a hidden subdir instead of
  leaving half-files in place.

---

## 10. Common recipes

```bash
# Local mirror with deletions, dry-run first
rsync -avn --delete /var/www/ /mnt/backup/www/   # preview
rsync -av  --delete /var/www/ /mnt/backup/www/   # commit

# Offsite push, throttled, compressed, over SSH
rsync -az --bwlimit=5000 -e ssh /var/www/ backup@offsite:/srv/backups/www/

# Integrity audit (should print nothing)
rsync -avnc /var/www/ /mnt/backup/www/

# Hard-linked daily snapshot (see incremental-snapshots.md)
rsync -a --delete --link-dest=/mnt/backup/2026-06-14 /var/www/ /mnt/backup/2026-06-15/
```

---

## Sources

- Sander van Vugt, *Red Hat RHCSA 8 Cert Guide (EX200)*, 2nd ed. — `rsync -a`
  over SSH for remote directory synchronization; SSH key-based auth flow.
- `rsync(1)` man page — flag semantics, filter rules, `--link-dest`,
  `--bwlimit`, `--partial`/`--append-verify`.
- Real-world experience running offsite rsync backups on production Linux
  servers.
