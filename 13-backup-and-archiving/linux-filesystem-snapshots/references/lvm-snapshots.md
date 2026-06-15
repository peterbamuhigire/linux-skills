# LVM snapshots

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

LVM block-level copy-on-write snapshots — the portable, always-available
point-in-time mechanism that works under **any** filesystem (ext4, xfs) on both
families. Day-to-day LVM volume/VG management (PV→VG→LV, resize, fstab) lives in
[`linux-disk-storage`](../../../06-storage-and-filesystems/linux-disk-storage/SKILL.md);
this file is the snapshot-specific deep dive.

## Table of contents

1. How an LVM snapshot works
2. Creating and sizing a snapshot
3. Backing up from a snapshot
4. Monitoring COW fill (the invalidation risk)
5. Quiescing a database first
6. Reverting (merge) a snapshot
7. Sources

---

## 1. How an LVM snapshot works

A snapshot LV is a copy-on-write view of an **origin** LV at the instant of
creation. LVM does not copy the data up front; instead, when a block on the
origin is about to be **overwritten**, the original block is first copied into
the snapshot's COW area. Reading the snapshot returns origin blocks for anything
unchanged, COW-stored blocks for anything that changed since.

Consequences:

- Creation is instant and cheap.
- Write activity on the origin during the snapshot's life **fills the COW area**.
- The COW area only needs to hold the *delta*, not the whole volume.

Conceptual note (Johnson, *Fedora Linux Essentials*): LVM snapshots incur
overhead proportional to volume size and I/O activity due to the COW operations
on the underlying block devices — unlike Btrfs/ZFS where snapshots are
first-class and near-free.

---

## 2. Creating and sizing a snapshot

```bash
# -s = snapshot, -L = COW size, -n = snapshot name, last arg = origin LV
sudo lvcreate -L 5G -s -n web-snap /dev/data/web

# Confirm
sudo lvs -o lv_name,origin,lv_size,data_percent /dev/data
```

Sizing rule of thumb: COW area ≥ 10–20% of the origin LV, more if writes are
heavy during the backup window. The COW only needs to absorb blocks changed on
the origin while the snapshot exists — for a 30-minute backup of a quiet volume,
small is fine; for a busy database, size generously.

---

## 3. Backing up from a snapshot

```bash
sudo mkdir -p /mnt/snap
sudo mount -o ro /dev/data/web-snap /mnt/snap      # mount read-only

# Archive the stable view (use tar metadata flags from linux-archive-integrity)
sudo tar --acls --xattrs -czf /backups/web-$(date +%F).tar.gz -C /mnt/snap .

sudo umount /mnt/snap
sudo lvremove -f /dev/data/web-snap                # ALWAYS release when done
```

For XFS snapshots, add `-o ro,nouuid` to the mount (XFS refuses to mount two
filesystems with the same UUID otherwise).

To get the data **offsite**, push the resulting archive with
[rsync](../../linux-rsync-sync/SKILL.md) — the snapshot itself is on the same VG
as production and is not a backup.

---

## 4. Monitoring COW fill (the invalidation risk)

**A full snapshot is silently invalidated** — LVM drops it and the snapshot
becomes unusable. Watch the `Data%` column:

```bash
sudo lvs                       # Data% = COW area fill
# LV       VG   Attr       LSize Origin Data%
# web      data owi-aos--- 50.00g
# web-snap data swi-a-s---  5.00g web    37.42
```

If `Data%` approaches 100%, either the backup is taking too long for the write
rate or the COW area was sized too small. Extend it live if needed:

```bash
sudo lvextend -L +2G /dev/data/web-snap
```

This is why LVM snapshots are for **short-lived backup windows**, not long-term
retention.

---

## 5. Quiescing a database first

A raw snapshot of a busy database can capture a mid-transaction state. Quiesce
first for a clean image:

```bash
# MySQL/MariaDB: flush + lock in one session, snapshot in another, then unlock
mysql -e 'FLUSH TABLES WITH READ LOCK; FLUSH LOGS;'   # hold this session open
sudo lvcreate -L 5G -s -n db-snap /dev/data/mysql      # in a second shell
mysql -e 'UNLOCK TABLES;'
```

Or prefer a logical dump (`mysqldump --single-transaction`) when the engine is
transactional (InnoDB) — often simpler than volume snapshots for DBs.

---

## 6. Reverting (merge) a snapshot

To roll the origin back to the snapshot's instant, **merge** it:

```bash
sudo umount /var/www                 # unmount origin if possible
sudo lvconvert --merge /dev/data/web-snap
# If the origin is in use (e.g. root), the merge completes on next reboot.
```

The merge is destructive of changes made since the snapshot. The snapshot is
consumed (removed) by the merge. Always back up before merging.

---

## Sources

- Richard Johnson, *Fedora Linux Essentials* — conceptual comparison of LVM
  block-level COW snapshots vs Btrfs/ZFS filesystem-level snapshots.
- `lvcreate(8)`, `lvs(8)`, `lvconvert(8)`, `lvextend(8)` man pages.
- Real-world experience taking LVM snapshots of live web/DB volumes for backup.
