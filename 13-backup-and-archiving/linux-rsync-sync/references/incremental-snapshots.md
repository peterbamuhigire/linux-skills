# rsync incremental snapshots (`--link-dest`)

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

How to build space-efficient, browsable, point-in-time backup snapshots with
`rsync --link-dest` — the model behind `rsnapshot` and Apple's Time Machine.
Companion to [`rsync-reference.md`](rsync-reference.md).

## Table of contents

1. The idea: hard-linked snapshots
2. A single snapshot run
3. A rotation script
4. Pruning / expiry
5. Verifying disk savings
6. Caveats
7. Sources

---

## 1. The idea: hard-linked snapshots

Each backup run creates a **complete directory tree**. But files that did not
change since the previous snapshot are stored as **hard links** to the previous
snapshot's copy — they share the same inode and cost no extra disk. Only
changed/new files consume new blocks.

Result: every snapshot looks and restores like a full backup, but N snapshots of
mostly-static data cost roughly "one full + the deltas".

```
/mnt/backup/2026-06-13/var/www/index.html   ─┐
/mnt/backup/2026-06-14/var/www/index.html   ─┼─ same inode (unchanged file)
/mnt/backup/2026-06-15/var/www/index.html   ─┘
/mnt/backup/2026-06-15/var/www/new.html      ── new inode (only this snapshot)
```

[GROUNDING-GAP: `--link-dest` hard-link/inode accounting and the rsnapshot
rotation design are from upstream rsync(1) man page and rsnapshot docs; deepen
with UNIX & Linux System Administration Handbook.]

---

## 2. A single snapshot run

```bash
SRC=/var/www/
DEST=/mnt/backup
TODAY=$DEST/$(date +%F)
LAST=$(ls -1d "$DEST"/20* 2>/dev/null | tail -1)   # newest existing snapshot

rsync -a --delete \
      ${LAST:+--link-dest="$LAST"} \
      "$SRC" "$TODAY/"
```

- `--delete` keeps each snapshot a faithful mirror of the source at that instant.
- `${LAST:+--link-dest=...}` adds the flag only if a previous snapshot exists
  (the first run is a plain full copy).
- `--link-dest` must be an **absolute path** or relative to the destination.

You can pass `--link-dest` more than once (rsync checks each in order) to link
against several prior snapshots.

---

## 3. A rotation script

```bash
#!/usr/bin/env bash
set -euo pipefail
SRC=/var/www/
DEST=/mnt/backup/www
KEEP=14                              # keep 14 daily snapshots

mkdir -p "$DEST"
TODAY="$DEST/$(date +%F)"
LAST=$(find "$DEST" -maxdepth 1 -type d -name '20*' | sort | tail -1)

rsync -a --delete ${LAST:+--link-dest="$LAST"} "$SRC" "$TODAY/"

# Expire oldest beyond KEEP
find "$DEST" -maxdepth 1 -type d -name '20*' | sort | head -n -"$KEEP" | \
    while read -r old; do rm -rf "$old"; done
```

Schedule with cron or a systemd timer (see the disaster-recovery
`backup-strategy.md` for timer patterns).

---

## 4. Pruning / expiry

Deleting an old snapshot directory is safe: hard-linked data survives until the
**last** snapshot referencing it is removed. `rm -rf /mnt/backup/www/2026-06-01`
only frees blocks for files unique to that day.

Grandfather-father-son rotation (keep 7 daily, 4 weekly, 12 monthly) works the
same way — just keep more snapshot directories and expire by age bucket.

---

## 5. Verifying disk savings

```bash
du -sh /mnt/backup/www/2026-06-15            # apparent size of one snapshot
du -sh --total /mnt/backup/www/*             # du counts shared inodes once
df -h /mnt/backup                            # real space used on the volume
```

`du` over the whole snapshot tree counts each shared inode only once, so the
total reflects real usage. A single snapshot's `du -sh` shows the full apparent
size (what you'd restore).

---

## 6. Caveats

- `--link-dest` and the destination must be on the **same filesystem** (hard
  links cannot cross filesystems).
- A snapshot tree is only as offsite as its volume — push the whole `$DEST` to
  another host/cloud for true 3-2-1.
- Permissions/ownership are preserved with `-a`; add `-AX` for ACLs/xattrs.
- This is not encrypted at rest. For an offsite encrypted copy, archive with
  [`../../linux-archive-integrity/SKILL.md`](../../linux-archive-integrity/SKILL.md)
  + GPG, or encrypt the backup volume.

---

## Sources

- `rsync(1)` man page — `--link-dest`, `--delete`, hard-link behaviour.
- rsnapshot design (the canonical hard-linked-snapshot implementation).
- Real-world experience running hard-linked rsync snapshot backups.
