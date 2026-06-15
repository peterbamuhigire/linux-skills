---
name: linux-rsync-sync
description: Advanced rsync for offsite and incremental backups on Debian/Ubuntu and RHEL-family servers (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). rsync itself is identical on both families; only the install package differs (rsync via apt vs dnf, and openssh-server for rsync-over-SSH). Covers archive mode (-a), checksum verification (--checksum), safe previews (--dry-run), bandwidth throttling (--bwlimit), mirror deletion (--delete), include/exclude filters (--exclude / --exclude-from), hard-linked incremental snapshots (--link-dest), rsync over SSH, and restartable/resumable transfers (--partial / --append-verify). Always dry-runs before a real --delete mirror.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# rsync Sync & Incremental Backup

## Distro support

Single-tool skill: `rsync` is byte-for-byte identical on both families. The only
differences are the install package and the SSH server package for
rsync-over-SSH. Body uses Debian/Ubuntu; the **RHEL family** (Fedora, RHEL,
CentOS Stream, Rocky, Alma, Oracle) equivalents are in the matrix.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Install rsync | `apt install rsync` | `dnf install rsync` |
| SSH server (for pull/push over SSH) | `apt install openssh-server` | `dnf install openssh-server` |
| Daemon unit (rsyncd, rarely used) | `rsync.service` | `rsyncd.service` |
| `rsync -a` archive mode | identical | identical |
| `--link-dest` / `--bwlimit` / `--checksum` / `--partial` | identical | identical |
| SELinux on the target | not enforcing | **enforcing** — restore contexts with `restorecon -R` after a cross-host copy |

**RHEL-family gotcha:** SELinux is enforcing. rsync preserves file *contents*
and (with `-a`) ownership/perms, but a file landing in a new path may carry the
wrong SELinux context. Run `restorecon -R <target>` after restoring into
SELinux-labelled trees such as `/var/www` or `/home`. The `-X` (xattrs) flag
preserves the context only when source and target both label the same way.

In `sk-*` scripts use the `common.sh` package primitives (`pkg_install`, etc.)
rather than hardcoding apt/dnf. See
[`../../10-automation-and-scripting/linux-bash-scripting/SKILL.md`](../../10-automation-and-scripting/linux-bash-scripting/SKILL.md)
and [`../../docs/multi-distro/plan.md`](../../docs/multi-distro/plan.md).

## Use when

- Mirroring a directory tree to another disk, host, or offsite target.
- Building space-efficient incremental snapshot backups with `--link-dest`.
- Resuming a large transfer that was interrupted, or throttling one so it does
  not saturate a production link.
- Verifying a copy by content (`--checksum`) rather than size/mtime.

## Do not use when

- You need a *restore* of an existing GPG-encrypted backup or an emergency
  recovery checklist; use
  [`../../09-troubleshooting-and-recovery/linux-disaster-recovery/SKILL.md`](../../09-troubleshooting-and-recovery/linux-disaster-recovery/SKILL.md).
- You need a single sealed, integrity-verified archive (tar.gz/tar.xz with
  checksums); use
  [`../linux-archive-integrity/SKILL.md`](../linux-archive-integrity/SKILL.md).
- You need a crash-consistent point-in-time image of a live database volume;
  use [`../linux-filesystem-snapshots/SKILL.md`](../linux-filesystem-snapshots/SKILL.md).

## Required inputs

- The source path and the destination (local path, or `user@host:path`).
- Whether the run is a one-shot mirror, a `--delete` mirror, or a `--link-dest`
  incremental snapshot.
- Any bandwidth ceiling, exclude list, and whether SSH transport is required.

## Workflow

1. Always `--dry-run` first, especially before any `--delete` mirror.
2. Run the real transfer with the smallest correct flag set.
3. For incrementals, point `--link-dest` at the previous snapshot directory.
4. Verify with a second `--dry-run` (should report nothing to do) or
   `--checksum`.

## Quality standards

- A trailing slash on the source means "contents of"; no slash means "the
  directory itself". Decide deliberately — this is the most common rsync bug.
- Preview `--delete` before running it. Deletion is unrecoverable.
- Throttle (`--bwlimit`) any transfer that shares a production link.

## Anti-patterns

- Running `--delete` without a prior `--dry-run`.
- Confusing `src/` and `src` and silently nesting or flattening the tree.
- Using `--size-only`/default mtime checks when bit-rot detection is the point
  (use `--checksum`).
- Treating an rsync mirror as a backup with history — a mirror has no
  point-in-time recovery unless you use `--link-dest` snapshots.

## Outputs

- The exact rsync command run and the dry-run preview that justified it.
- Bytes transferred, files deleted (if any), and the verification result.
- The snapshot directory created, for incremental runs.

## References

- [`references/rsync-reference.md`](references/rsync-reference.md)
- [`references/incremental-snapshots.md`](references/incremental-snapshots.md)

**This skill is self-contained.** Every command below is stock `rsync` on both
families (the body shows Debian/Ubuntu; see **Distro support** above for the
RHEL-family install). The `sk-rsync-backup` script in the **Optional fast path**
section is a convenience wrapper — never required.

## Archive Mode (the baseline)

```bash
# -a = archive: -rlptgoD (recurse, links, perms, times, group, owner, devices).
# This is the correct default for backups: it preserves metadata.
rsync -a /var/www/ /mnt/backup/www/

# -v verbose, -h human sizes, --progress per-file progress, --stats summary
rsync -avh --progress --stats /var/www/ /mnt/backup/www/
```

> **Trailing slash matters.** `rsync -a src/ dst/` copies the *contents* of
> `src` into `dst`. `rsync -a src dst/` creates `dst/src/`. Get this wrong and
> you either flatten or double-nest the tree.

---

## Dry Run First (always, before --delete)

```bash
# Show exactly what WOULD change, transfer nothing:
rsync -avn --delete /var/www/ /mnt/backup/www/
#       ^^ -n = --dry-run

# Read the itemized change list (-i): >f+++++++ = new file, *deleting = removed
rsync -ain --delete /var/www/ /mnt/backup/www/
```

Only after the dry-run output is what you expect, drop the `-n` and run for
real.

---

## Mirror With --delete

```bash
# Make dst an EXACT copy of src — files removed from src are removed from dst.
rsync -a --delete /var/www/ /mnt/backup/www/

# Safety net: move deletions aside instead of removing them
rsync -a --delete --backup --backup-dir=/mnt/backup/deleted-$(date +%F) \
      /var/www/ /mnt/backup/www/
```

`--delete` is destructive on the destination. Never run it without a prior
`--dry-run`.

---

## Exclude Filters

```bash
# Inline excludes (repeatable)
rsync -a --exclude='node_modules' --exclude='*.log' --exclude='/cache/' \
      /var/www/ /mnt/backup/www/

# From a file — one pattern per line, '#' comments allowed
rsync -a --exclude-from=/etc/backup-excludes.txt /var/www/ /mnt/backup/www/
```

```text
# /etc/backup-excludes.txt
node_modules
vendor/
.git/
*.tmp
/var/cache/
```

A leading `/` anchors the pattern to the transfer root; without it the pattern
matches at any depth.

---

## Checksum Verification

```bash
# Default: rsync decides "changed" by size + mtime (fast).
# --checksum: compare a full checksum of every file (slow, catches bit-rot
# and clock-skew cases where size+mtime lie). Use for integrity audits.
rsync -avc /var/www/ /mnt/backup/www/
```

A good post-backup integrity check: `rsync -avnc src/ dst/` — if it reports any
files to transfer, the destination has drifted from the source.

---

## Bandwidth Throttling

```bash
# Cap at 5000 KB/s (~5 MB/s) so a backup never saturates a production uplink.
rsync -a --bwlimit=5000 /var/www/ backup@offsite:/srv/backups/www/

# --bwlimit takes KB/s by default; suffixes allowed: --bwlimit=5M
```

[GROUNDING-GAP: `--bwlimit` units, the leaky-bucket behaviour, and interaction
with `--whole-file`/SSH compression are from upstream rsync(1) man page; deepen
with UNIX & Linux System Administration Handbook.]

---

## Incremental Snapshots With --link-dest

`--link-dest` makes unchanged files **hard links** to the previous snapshot, so
each daily snapshot is a complete browsable tree but only consumes disk for the
files that actually changed. This is the classic `rsnapshot`/Time Machine model.

```bash
DEST=/mnt/backup/snapshots
TODAY=$DEST/$(date +%F)
LAST=$(ls -1d "$DEST"/20* 2>/dev/null | tail -1)   # most recent prior snapshot

rsync -a --delete \
      ${LAST:+--link-dest="$LAST"} \
      /var/www/ "$TODAY/"
```

Each `$TODAY` is a full snapshot you can browse and restore from directly; only
changed files cost extra disk. Delete an old snapshot dir to expire it — hard
links mean shared data survives until the last referencing snapshot is gone.

[GROUNDING-GAP: `--link-dest` (and multiple `--link-dest` dirs, the
hard-link/inode accounting, and pruning semantics) is from upstream rsync(1)
man page and the rsnapshot design; deepen with UNIX & Linux System
Administration Handbook.]

Full snapshot rotation strategy: [`references/incremental-snapshots.md`](references/incremental-snapshots.md).

---

## rsync Over SSH

```bash
# Push to a remote host (rsync uses ssh as the transport by default for host:path)
rsync -a -e ssh /var/www/ backup@offsite:/srv/backups/www/

# Pull from a remote host
rsync -a backup@offsite:/srv/backups/www/ /var/www/

# Non-standard SSH port and an identity key
rsync -a -e 'ssh -p 2222 -i ~/.ssh/backup_ed25519' /var/www/ backup@offsite:/srv/backups/www/

# -z compress in transit (skip for already-compressed data / fast LANs)
rsync -az -e ssh /var/www/ backup@offsite:/srv/backups/www/
```

Grounded in the RHCSA flow: `rsync -a server2:/etc/ /tmp` synchronizes a remote
directory locally over SSH (Sander van Vugt, RHCSA 8 Cert Guide).

---

## Restartable / Resumable Transfers

```bash
# --partial keeps a partially transferred file so the next run resumes it
# instead of starting over. --append-verify resumes AND checksums the existing
# bytes. --progress shows where it is.
rsync -a --partial --append-verify --progress \
      bigfile.img backup@offsite:/srv/backups/

# Convenience bundle for flaky links: -P = --partial --progress
rsync -aP big-dir/ backup@offsite:/srv/backups/big-dir/

# Run again after an interruption — it picks up where it left off.
```

Full flag reference and the source-trailing-slash rules:
[`references/rsync-reference.md`](references/rsync-reference.md).

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-rsync-sync` installs:

| Task | Fast-path script |
|---|---|
| Dry-run-first mirror or `--link-dest` snapshot, bwlimit-aware | `sudo sk-rsync-backup --src /var/www --dst /mnt/backup/www` |

This is an optional wrapper around the `rsync` commands above.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-rsync-sync
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-rsync-backup | scripts/sk-rsync-backup.sh | no | Wrapper around `rsync -a`: ALWAYS previews with `--dry-run` and asks before a real run; supports `--delete` mirror or `--link-dest` incremental snapshot mode, `--bwlimit` throttling, `--exclude-from`, and SSH targets (`user@host:path`). Verifies with a post-run dry-run. |
